/**
 * Header Rebuilding Plugin
 *
 * Removes all traces of AMS Enterprise from email headers
 * Generates new Message-ID to hide original source
 * Preserves required headers (From, To, Subject, etc.)
 */

const crypto = require('crypto');

exports.register = function() {
  this.loginfo('Header Rebuilder plugin loaded');
};

exports.hook_data_post = function(next, connection) {
  const plugin = this;

  try {
    const parsed = connection.transaction.notes.parsed_email;

    if (!parsed) {
      plugin.logerror('No parsed email data found');
      return next(DENYSOFT, 'Email parsing required before header rebuild');
    }

    // Generate new Message-ID
    const newMessageId = generateMessageId();

    // Build clean headers object
    const cleanHeaders = {
      // Required headers (preserve from original)
      from: parsed.headers.from,
      to: parsed.headers.to,
      subject: parsed.headers.subject,
      date: parsed.headers.date || new Date().toUTCString(),

      // New Message-ID (replaces AMS Message-ID)
      messageId: newMessageId,

      // Optional headers (preserve if present)
      cc: parsed.headers.cc || null,
      bcc: parsed.headers.bcc || null,
      replyTo: parsed.headers.replyTo || null,

      // MIME headers
      mimeVersion: '1.0',
      contentType: determineContentType(parsed),

      // Our own identification (optional)
      xMailer: 'Postal Mail Server'
    };

    // Remove AMS-specific headers
    const removedHeaders = [];

    // List of headers to remove (AMS traces)
    const headersToRemove = [
      /^received$/i,           // All Received headers
      /^x-ams-/i,             // X-AMS-* headers
      /^x-original-/i,        // X-Original-* headers
      /^return-path$/i,       // Will be set by Postal
      /^authentication-results$/i,
      /^arc-/i,               // ARC headers
      /^dkim-signature$/i,    // Old DKIM (Postal will re-sign)
      /^domainkey-signature$/i
    ];

    // Check which headers were removed
    if (parsed.raw && parsed.raw.headers) {
      Object.keys(parsed.raw.headers).forEach(header => {
        if (headersToRemove.some(pattern => pattern.test(header))) {
          removedHeaders.push(header);
        }
      });
    }

    // Store cleaned headers
    connection.transaction.notes.clean_headers = cleanHeaders;

    // Store original Message-ID for tracking
    connection.transaction.notes.original_message_id = parsed.headers.messageId;

    // Store new Message-ID
    connection.transaction.notes.new_message_id = newMessageId;

    // Log what was done
    plugin.loginfo(`Headers rebuilt for: ${parsed.headers.subject || '(no subject)'}`);
    plugin.loginfo(`  Old Message-ID: ${parsed.headers.messageId || 'none'}`);
    plugin.loginfo(`  New Message-ID: ${newMessageId}`);
    plugin.loginfo(`  Removed headers: ${removedHeaders.length}`);

    if (removedHeaders.length > 0) {
      plugin.logdebug(`  Removed: ${removedHeaders.join(', ')}`);
    }

    next(OK);

  } catch (error) {
    plugin.logerror(`Header rebuild error: ${error.message}`);
    next(DENYSOFT, 'Error rebuilding headers');
  }
};

/**
 * Generate new Message-ID
 * Format: <local_{random24hex}@domain>
 */
function generateMessageId() {
  const randomHex = crypto.randomBytes(12).toString('hex'); // 24 hex chars
  const domain = process.env.DOMAIN || 'linenarrow.com';
  return `<local_${randomHex}@${domain}>`;
}

/**
 * Determine Content-Type based on email content
 */
function determineContentType(parsed) {
  const hasHtml = parsed.body.html && parsed.body.html.length > 0;
  const hasText = parsed.body.text && parsed.body.text.length > 0;
  const hasAttachments = parsed.attachments && parsed.attachments.length > 0;

  if (hasAttachments) {
    // Multipart/mixed for attachments
    return 'multipart/mixed';
  } else if (hasHtml && hasText) {
    // Multipart/alternative for both HTML and text
    return 'multipart/alternative';
  } else if (hasHtml) {
    return 'text/html; charset=UTF-8';
  } else {
    return 'text/plain; charset=UTF-8';
  }
}
