/**
 * Forward to API Plugin
 *
 * Forwards processed email to Rails API
 * Sends JSON payload with all email data
 */

const axios = require('axios');

// API configuration
const API_URL = process.env.API_URL || 'http://api:3000';
const API_KEY = process.env.SMTP_RELAY_API_KEY || '';

exports.register = function() {
  this.loginfo('Forward to API plugin loaded');
  this.loginfo(`API URL: ${API_URL}`);
};

exports.hook_queue = async function(next, connection) {
  const plugin = this;

  try {
    const parsed = connection.transaction.notes.parsed_email;
    const cleanHeaders = connection.transaction.notes.clean_headers;
    const modifiedBody = connection.transaction.notes.modified_body;
    const trackingInfo = connection.transaction.notes.tracking_info;
    const envelope = connection.transaction.notes.envelope;

    // Validate we have all required data
    if (!parsed || !cleanHeaders || !modifiedBody || !envelope) {
      plugin.logerror('Missing required data from previous plugins');
      return next(DENYSOFT, 'Email processing incomplete');
    }

    // Build payload for Rails API
    const payload = {
      envelope: {
        from: envelope.from,
        to: envelope.to
      },

      headers: {
        from: cleanHeaders.from,
        to: cleanHeaders.to,
        cc: cleanHeaders.cc,
        subject: cleanHeaders.subject,
        message_id: cleanHeaders.messageId,
        date: cleanHeaders.date,
        reply_to: cleanHeaders.replyTo
      },

      body: {
        plain: modifiedBody.text || '',
        html: modifiedBody.html || ''
      },

      attachments: parsed.attachments || [],

      tracking: {
        campaign_id: trackingInfo?.campaignId || 'unknown',
        message_id: trackingInfo?.messageId || cleanHeaders.messageId.replace(/<|>/g, ''),
        affiliate_id: trackingInfo?.affiliateId,
        recipient_id: trackingInfo?.recipientId,
        original_message_id: connection.transaction.notes.original_message_id
      },

      metadata: {
        smtp_credential_id: connection.notes.smtp_credential_id,
        auth_user: connection.notes.auth_user,
        received_at: new Date().toISOString(),
        remote_ip: connection.remote.ip,
        remote_host: connection.remote.host
      }
    };

    // Send to Rails API
    const startTime = Date.now();

    const response = await axios.post(
      `${API_URL}/api/v1/smtp/receive`,
      payload,
      {
        headers: {
          'Authorization': `Bearer ${API_KEY}`,
          'Content-Type': 'application/json',
          'User-Agent': 'SMTP-Relay/1.0'
        },
        timeout: 30000 // 30 second timeout
      }
    );

    const duration = Date.now() - startTime;

    // Log success
    plugin.loginfo(`Email forwarded to API (${duration}ms)`);
    plugin.loginfo(`  Subject: ${cleanHeaders.subject || '(no subject)'}`);
    plugin.loginfo(`  From: ${cleanHeaders.from}`);
    plugin.loginfo(`  To: ${envelope.to.join(', ')}`);
    plugin.loginfo(`  Message ID: ${trackingInfo.messageId}`);
    plugin.loginfo(`  API Response: ${response.status} ${response.statusText}`);

    if (response.data && response.data.message_id) {
      plugin.loginfo(`  Queued as: ${response.data.message_id}`);
    }

    // Store API response
    connection.transaction.notes.api_response = response.data;

    // Return OK to accept the email
    next(OK, `Message queued as ${response.data.message_id || 'unknown'}`);

  } catch (error) {
    plugin.logerror(`Error forwarding to API: ${error.message}`);

    // Log detailed error info
    if (error.response) {
      plugin.logerror(`  Status: ${error.response.status}`);
      plugin.logerror(`  Data: ${JSON.stringify(error.response.data)}`);
    } else if (error.request) {
      plugin.logerror(`  No response received from API`);
    }

    // Return temporary error (allows retry)
    return next(DENYSOFT, 'Temporary error processing email. Please try again later.');
  }
};

/**
 * Hook to log successful queue
 */
exports.hook_queue_ok = function(next, connection) {
  const apiResponse = connection.transaction.notes.api_response;

  this.loginfo('Email successfully queued');

  if (apiResponse) {
    this.loginfo(`API Response: ${JSON.stringify(apiResponse, null, 2)}`);
  }

  next();
};

/**
 * Hook to handle queue errors
 */
exports.hook_queue_error = function(next, connection, error) {
  this.logerror(`Queue error: ${error.message}`);

  // Return error to sender
  next();
};
