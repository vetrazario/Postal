/**
 * Email Parsing Plugin
 *
 * Parses MIME structure of incoming emails
 * Extracts headers, body parts (plain/html), and attachments
 */

const { simpleParser } = require('mailparser');
const stream = require('stream');

exports.register = function() {
  this.loginfo('Email Parser plugin loaded');
};

exports.hook_data_post = function(next, connection) {
  const plugin = this;

  try {
    // Get email data from connection
    const emailData = connection.transaction.message_stream;

    // Convert to buffer for parsing
    const chunks = [];
    emailData.on('data', (chunk) => chunks.push(chunk));

    emailData.on('end', async () => {
      try {
        const buffer = Buffer.concat(chunks);

        // Parse email using mailparser
        const parsed = await simpleParser(buffer);

      // Store parsed data in connection notes for next plugins
      connection.transaction.notes.parsed_email = {
        // Headers
        headers: {
          from: parsed.from?.text || '',
          to: parsed.to?.text || '',
          cc: parsed.cc?.text || '',
          bcc: parsed.bcc?.text || '',
          subject: parsed.subject || '',
          messageId: parsed.messageId || '',
          date: parsed.date || new Date(),
          replyTo: parsed.replyTo?.text || '',
          inReplyTo: parsed.inReplyTo || '',
          references: parsed.references || []
        },

        // Body content
        body: {
          text: parsed.text || '',
          html: parsed.html || '',
          textAsHtml: parsed.textAsHtml || ''
        },

        // Attachments
        attachments: (parsed.attachments || []).map(att => ({
          filename: att.filename || 'untitled',
          contentType: att.contentType || 'application/octet-stream',
          size: att.size || 0,
          content: att.content ? att.content.toString('base64') : '',
          contentDisposition: att.contentDisposition || 'attachment',
          contentId: att.contentId || null,
          cid: att.cid || null
        })),

        // Original MIME structure (for reference)
        raw: {
          headerLines: parsed.headerLines || [],
          headers: Object.fromEntries(parsed.headers || [])
        }
      };

      // Extract envelope addresses if not already set
      if (!connection.transaction.notes.envelope) {
        connection.transaction.notes.envelope = {
          from: connection.transaction.mail_from?.address || extractEmail(parsed.from?.text),
          to: connection.transaction.rcpt_to?.map(r => r.address) || extractEmails(parsed.to?.text)
        };
      }

        // Log successful parsing
        plugin.loginfo(`Parsed email: ${parsed.subject || '(no subject)'}`);
        plugin.loginfo(`  From: ${parsed.from?.text || 'unknown'}`);
        plugin.loginfo(`  To: ${parsed.to?.text || 'unknown'}`);
        plugin.loginfo(`  Attachments: ${parsed.attachments?.length || 0}`);
        plugin.loginfo(`  Size: ${formatBytes(buffer.length)}`);

        next(OK);
      } catch (parseError) {
        plugin.logerror(`Error parsing email: ${parseError.message}`);
        next(DENYSOFT, 'Error parsing email');
      }
    });

    emailData.on('error', (err) => {
      plugin.logerror(`Error reading email data: ${err.message}`);
      next(DENYSOFT, 'Error processing email');
    });

  } catch (error) {
    plugin.logerror(`Parse error: ${error.message}`);
    next(DENYSOFT, 'Error parsing email');
  }
};

// Helper function to extract single email address
function extractEmail(text) {
  if (!text) return '';
  const match = text.match(/<(.+?)>/) || text.match(/([^\s<>]+@[^\s<>]+)/);
  return match ? match[1] : text.trim();
}

// Helper function to extract multiple email addresses
function extractEmails(text) {
  if (!text) return [];
  const emails = text.split(',').map(e => extractEmail(e)).filter(Boolean);
  return emails;
}

// Helper function to format bytes
function formatBytes(bytes) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}
