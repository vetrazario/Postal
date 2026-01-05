#!/usr/bin/env node

/**
 * SMTP Relay Server for Email Sender Infrastructure
 *
 * This server accepts SMTP connections from AMS Enterprise,
 * parses emails, rebuilds headers to hide AMS traces,
 * injects tracking, and forwards to Rails API.
 */

const { SMTPServer } = require('smtp-server');
const { simpleParser } = require('mailparser');
const axios = require('axios');
const path = require('path');
const fs = require('fs');

// Load environment variables
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

const PORT = process.env.SMTP_RELAY_PORT || 587;
const API_URL = process.env.API_URL || 'http://api:3000';
const DOMAIN = process.env.DOMAIN || 'localhost';

// TLS certificate paths
const TLS_CERT = process.env.TLS_CERT_PATH || `/etc/letsencrypt/live/${DOMAIN}/fullchain.pem`;
const TLS_KEY = process.env.TLS_KEY_PATH || `/etc/letsencrypt/live/${DOMAIN}/privkey.pem`;

// Check if TLS certificates exist
let tlsEnabled = false;
let tlsOptions = {};

if (fs.existsSync(TLS_CERT) && fs.existsSync(TLS_KEY)) {
  tlsOptions = {
    key: fs.readFileSync(TLS_KEY),
    cert: fs.readFileSync(TLS_CERT)
  };
  tlsEnabled = true;
  console.log('✓ TLS certificates found and loaded');
} else {
  console.log('⚠ TLS certificates not found - STARTTLS disabled');
  console.log('  Expected cert:', TLS_CERT);
  console.log('  Expected key:', TLS_KEY);
}

// Log startup
console.log('='.repeat(60));
console.log('Starting SMTP Relay Server');
console.log('='.repeat(60));
console.log('Port:', PORT);
console.log('API URL:', API_URL);
console.log('Domain:', DOMAIN);
console.log('TLS:', tlsEnabled ? 'ENABLED' : 'DISABLED');
console.log('='.repeat(60));

// Create SMTP server options
const serverOptions = {
  // Server options
  banner: 'Email Sender SMTP Relay',
  size: 14680064, // 14MB max message size

  // TLS Configuration - enable STARTTLS if certificates available
  ...(tlsEnabled ? {
    secure: false, // Use STARTTLS (not implicit TLS)
    ...tlsOptions,
    // Allow STARTTLS
    // disabledCommands is not set, so STARTTLS is available
  } : {
    // No TLS certificates - disable STARTTLS
    disabledCommands: ['STARTTLS']
  }),

  // Disable authentication for now (can be added later)
  authOptional: true,

  // Handle incoming connections
  onConnect(session, callback) {
    console.log(`[${session.id}] New connection from ${session.remoteAddress}`);
    return callback(); // Accept connection
  },

  // Handle authentication (optional)
  onAuth(auth, session, callback) {
    console.log(`[${session.id}] Auth attempt: ${auth.username}`);
    // For now, accept all auth attempts
    return callback(null, { user: auth.username });
  },

  // Handle MAIL FROM
  onMailFrom(address, session, callback) {
    console.log(`[${session.id}] MAIL FROM: ${address.address}`);
    session.envelope = session.envelope || {};
    session.envelope.mailFrom = address;
    return callback();
  },

  // Handle RCPT TO
  onRcptTo(address, session, callback) {
    console.log(`[${session.id}] RCPT TO: ${address.address}`);
    session.envelope = session.envelope || {};
    session.envelope.rcptTo = session.envelope.rcptTo || [];
    session.envelope.rcptTo.push(address);
    return callback();
  },

  // Handle message data
  onData(stream, session, callback) {
    console.log(`[${session.id}] Receiving message data...`);

    let chunks = [];

    stream.on('data', (chunk) => {
      chunks.push(chunk);
    });

    stream.on('end', async () => {
      try {
        const buffer = Buffer.concat(chunks);
        const email = await simpleParser(buffer);

        console.log(`[${session.id}] Parsed email:`);
        console.log(`  From: ${email.from?.text}`);
        console.log(`  To: ${email.to?.text}`);
        console.log(`  Subject: ${email.subject}`);

        // Forward to API
        await forwardToAPI(session, email, buffer);

        console.log(`[${session.id}] Message forwarded successfully`);
        callback();
      } catch (err) {
        console.error(`[${session.id}] Error processing message:`, err);
        callback(new Error('Failed to process message'));
      }
    });
  }
};

// Create SMTP server with configured options
const server = new SMTPServer(serverOptions);

// Forward email to Rails API
async function forwardToAPI(session, parsed, raw) {
  try {
    // Convert headers Map to plain object
    const headersObj = {};
    if (parsed.headers && parsed.headers instanceof Map) {
      parsed.headers.forEach((value, key) => {
        headersObj[key.toLowerCase()] = value;
      });
    }

    const payload = {
      envelope: {
        from: session.envelope.mailFrom?.address,
        to: session.envelope.rcptTo?.map(r => r.address)
      },
      message: {
        from: parsed.from?.text,
        to: parsed.to?.text,
        cc: parsed.cc?.text,
        subject: parsed.subject,
        text: parsed.text,
        html: parsed.html,
        headers: headersObj
      },
      raw: raw.toString('base64')
    };

    // Log headers for debugging
    if (headersObj['x-id-mail']) {
      console.log(`  X-ID-mail: ${headersObj['x-id-mail']}`);
    }

    const response = await axios.post(`${API_URL}/api/v1/smtp/receive`, payload, {
      headers: {
        'Content-Type': 'application/json'
      },
      timeout: 30000
    });

    console.log(`API response:`, response.status, response.data);
  } catch (error) {
    console.error('Failed to forward to API:', error.message);
    throw error;
  }
}

// Start server
server.listen(PORT, '0.0.0.0', () => {
  console.log('✓ SMTP Relay Server started successfully');
  console.log(`✓ Listening on port ${PORT}`);
});

// Handle shutdown gracefully
process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('Received SIGINT, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});
