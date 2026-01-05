/**
 * Tracking Injection Plugin
 *
 * Injects tracking pixel for open tracking
 * Rewrites all links for click tracking
 */

const crypto = require('crypto');

exports.register = function() {
  this.loginfo('Tracking Injection plugin loaded');
};

exports.hook_data_post = function(next, connection) {
  const plugin = this;

  try {
    const parsed = connection.transaction.notes.parsed_email;
    const cleanHeaders = connection.transaction.notes.clean_headers;

    if (!parsed || !cleanHeaders) {
      return next(DENYSOFT, 'Previous plugins required before tracking injection');
    }

    // Extract tracking info from custom headers (if AMS sends them)
    const trackingInfo = extractTrackingInfo(parsed.raw.headers);

    // Get recipient email
    const recipientEmail = connection.transaction.notes.envelope?.to?.[0] ||
                          extractFirstEmail(parsed.headers.to);

    // Get message ID (use our new one)
    const messageId = connection.transaction.notes.new_message_id?.replace(/<|>/g, '') ||
                     generateTrackingId();

    // Build tracking parameters
    const trackingParams = {
      email: recipientEmail,
      messageId: messageId,
      campaignId: trackingInfo.campaignId || 'unknown',
      affiliateId: trackingInfo.affiliateId || null
    };

    // Inject tracking into HTML body
    let htmlBody = parsed.body.html || '';
    let plainBody = parsed.body.text || '';

    if (htmlBody) {
      // Rewrite all links for click tracking (before adding unsubscribe)
      htmlBody = rewriteLinks(htmlBody, trackingParams);

      // Inject unsubscribe link at the bottom
      htmlBody = injectUnsubscribeLink(htmlBody, trackingParams);

      // Inject tracking pixel (last, so it's at the very end)
      htmlBody = injectTrackingPixel(htmlBody, trackingParams);
    }

    // Store modified bodies
    connection.transaction.notes.modified_body = {
      html: htmlBody,
      text: plainBody,
      hasTracking: htmlBody.length > 0
    };

    // Store tracking info for API
    connection.transaction.notes.tracking_info = trackingParams;

    plugin.loginfo(`Tracking injected for: ${recipientEmail}`);
    plugin.loginfo(`  Campaign: ${trackingParams.campaignId}`);
    plugin.loginfo(`  Message ID: ${trackingParams.messageId}`);

    next(OK);

  } catch (error) {
    plugin.logerror(`Tracking injection error: ${error.message}`);
    next(DENYSOFT, 'Error injecting tracking');
  }
};

/**
 * Extract tracking information from headers
 * AMS may send custom headers like X-Campaign-ID, X-Affiliate-ID
 */
function extractTrackingInfo(headers) {
  const info = {
    campaignId: null,
    affiliateId: null,
    recipientId: null
  };

  if (!headers) return info;

  // Look for common tracking headers
  const headerMap = Object.fromEntries(
    Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v])
  );

  info.campaignId = headerMap['x-campaign-id'] ||
                    headerMap['x-campaign'] ||
                    headerMap['x-ams-campaign-id'];

  info.affiliateId = headerMap['x-affiliate-id'] ||
                     headerMap['x-affiliate'] ||
                     headerMap['x-ams-affiliate-id'];

  info.recipientId = headerMap['x-recipient-id'] ||
                     headerMap['x-ams-recipient-id'];

  return info;
}

/**
 * Inject tracking pixel before </body> tag
 */
function injectTrackingPixel(html, params) {
  const domain = process.env.DOMAIN || 'linenarrow.com';

  const trackingUrl = buildTrackingUrl('/track/o', {
    eid: base64Encode(params.email),
    mid: base64Encode(params.messageId),
    cid: base64Encode(params.campaignId)
  });

  const pixel = `<img src="https://${domain}${trackingUrl}" width="1" height="1" alt="" style="display:block;width:1px;height:1px;" />`;

  // Try to insert before </body>
  if (html.includes('</body>')) {
    return html.replace('</body>', `${pixel}\n</body>`);
  }

  // If no </body>, append to end
  return html + '\n' + pixel;
}

/**
 * Inject unsubscribe link before </body> tag
 */
function injectUnsubscribeLink(html, params) {
  const domain = process.env.DOMAIN || 'linenarrow.com';

  const unsubscribeUrl = `https://${domain}/unsubscribe?eid=${base64Encode(params.email)}&cid=${base64Encode(params.campaignId)}`;

  const unsubscribeHtml = `
<div style="text-align:center;padding:20px 0;margin-top:20px;border-top:1px solid #eee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:12px;color:#999;">
  <p style="margin:0 0 8px 0;">If you no longer wish to receive these emails, you can</p>
  <a href="${unsubscribeUrl}" style="color:#666;text-decoration:underline;">unsubscribe here</a>
</div>`;

  // Try to insert before </body>
  if (html.includes('</body>')) {
    return html.replace('</body>', `${unsubscribeHtml}\n</body>`);
  }

  // If no </body>, append to end
  return html + '\n' + unsubscribeHtml;
}

/**
 * Rewrite all <a href> links for click tracking
 */
function rewriteLinks(html, params) {
  const domain = process.env.DOMAIN || 'linenarrow.com';

  // Find all <a href="..."> tags
  return html.replace(/<a\s+([^>]*?)href="([^"]+)"([^>]*)>/gi, (match, before, url, after) => {
    // Skip tracking URLs (don't double-track)
    if (url.includes('/track/')) {
      return match;
    }

    // Skip mailto: and tel: links
    if (url.startsWith('mailto:') || url.startsWith('tel:')) {
      return match;
    }

    // Skip anchors (#)
    if (url.startsWith('#')) {
      return match;
    }

    // Skip unsubscribe links (they should not be tracked)
    if (url.includes('/unsubscribe') || url.includes('unsubscribe')) {
      return match;
    }

    // Build tracking URL
    const trackingUrl = buildTrackingUrl('/track/c', {
      url: base64Encode(url),
      eid: base64Encode(params.email),
      mid: base64Encode(params.messageId),
      cid: base64Encode(params.campaignId)
    });

    // Replace with tracked URL
    return `<a ${before}href="https://${domain}${trackingUrl}"${after}>`;
  });
}

/**
 * Build tracking URL with query parameters
 */
function buildTrackingUrl(path, params) {
  const query = Object.entries(params)
    .filter(([k, v]) => v)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');

  return `${path}?${query}`;
}

/**
 * Base64 encode (URL-safe)
 */
function base64Encode(str) {
  return Buffer.from(str).toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

/**
 * Extract first email address from string
 */
function extractFirstEmail(text) {
  if (!text) return 'unknown@example.com';
  const match = text.match(/<(.+?)>/) || text.match(/([^\s<>]+@[^\s<>]+)/);
  return match ? match[1] : text.trim();
}

/**
 * Generate random tracking ID
 */
function generateTrackingId() {
  return crypto.randomBytes(12).toString('hex');
}
