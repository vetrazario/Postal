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

// Normalize MAIL FROM so strict parser accepts AMS clients that send display-name or invalid syntax
function normalizeMailFromCommand(command) {
  if (!command || typeof command !== 'string') return command;
  const match = command.match(/^MAIL\s+FROM\s*:\s*(.+)$/i);
  if (!match) return command;
  const rest = match[1].trim();
  const firstToken = rest.split(/\s+/)[0];
  const remainder = rest.slice(firstToken.length).trim();
  const suffix = remainder ? ' ' + remainder : '';
  if (firstToken === '<>' || firstToken === '') return 'MAIL FROM:<>' + suffix;
  const inAngle = firstToken.match(/<([^>]*)>/);
  const inner = inAngle ? inAngle[1].trim() : firstToken;
  const addrSpec = inner.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/);
  if (addrSpec) return 'MAIL FROM:<' + addrSpec[0] + '>' + suffix;
  if (/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(inner)) return 'MAIL FROM:<' + inner + '>' + suffix;
  return 'MAIL FROM:<>' + suffix;
}

try {
  const pkgRoot = path.dirname(require.resolve('smtp-server'));
  const connModule = require(path.join(pkgRoot, 'smtp-connection.js'));
  // Handle both `module.exports = Class` and `module.exports = { SMTPConnection: Class }`
  const SMTPConnection = connModule.SMTPConnection || connModule;
  if (typeof SMTPConnection === 'function' && SMTPConnection.prototype._parseAddressCommand) {
    const originalParse = SMTPConnection.prototype._parseAddressCommand;
    SMTPConnection.prototype._parseAddressCommand = function (name, command) {
      if (name === 'MAIL FROM' && command) {
        const normalized = normalizeMailFromCommand(command);
        if (normalized !== command) {
          console.log(`Normalized MAIL FROM: "${command}" -> "${normalized}"`);
        }
        command = normalized;
      }
      return originalParse.call(this, name, command);
    };
    console.log('✓ MAIL FROM parser patched successfully');
  } else {
    console.warn('⚠ SMTPConnection class found but _parseAddressCommand not available');
    console.warn('  Module type:', typeof SMTPConnection, '| Keys:', Object.keys(connModule));
  }
} catch (e) {
  console.warn('Could not patch smtp-server MAIL FROM parser:', e.message);
}

// Load environment variables
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

const crypto = require('crypto');

const PORT = process.env.SMTP_RELAY_PORT || 587;
const API_URL = process.env.API_URL || 'http://api:3000';
const DOMAIN = process.env.DOMAIN || 'localhost';

// Authentication settings
const SMTP_AUTH_REQUIRED = process.env.SMTP_AUTH_REQUIRED !== 'false';
const SMTP_RELAY_SECRET = process.env.SMTP_RELAY_SECRET || '';
// Credentials are now validated via API against SmtpCredential model (managed in Dashboard)

// Rate limiting
const connectionAttempts = new Map();
const MAX_AUTH_FAILURES = 5;
const AUTH_BLOCK_DURATION = 300000; // 5 minutes

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
console.log('Auth Required:', SMTP_AUTH_REQUIRED ? 'YES' : 'NO');
console.log('Auth Mode: API (credentials managed via Dashboard)');
console.log('HMAC Secret:', SMTP_RELAY_SECRET ? 'CONFIGURED' : 'NOT SET (WARNING!)');
console.log('='.repeat(60));

// Async function to authenticate against API
async function authenticateViaAPI(username, password) {
  try {
    const response = await axios.post(`${API_URL}/api/v1/internal/smtp_auth`, {
      username: username,
      password: password
    }, {
      timeout: 5000
    });

    if (response.data.success) {
      return {
        success: true,
        username: response.data.username,
        rateLimit: response.data.rate_limit
      };
    }
    return { success: false, error: response.data.error || 'Authentication failed' };
  } catch (error) {
    if (error.response && error.response.status === 401) {
      return { success: false, error: 'Invalid credentials' };
    }
    console.error('API auth error:', error.message);
    return { success: false, error: 'Authentication service unavailable' };
  }
}

// Helper functions
function isBlocked(ip) {
  const attempts = connectionAttempts.get(ip);
  if (!attempts) return false;
  if (attempts.failures >= MAX_AUTH_FAILURES) {
    if (Date.now() - attempts.lastFailure < AUTH_BLOCK_DURATION) {
      return true;
    }
    // Reset after block duration
    connectionAttempts.delete(ip);
  }
  return false;
}

function recordAuthFailure(ip) {
  const attempts = connectionAttempts.get(ip) || { failures: 0, lastFailure: 0 };
  attempts.failures++;
  attempts.lastFailure = Date.now();
  connectionAttempts.set(ip, attempts);
  console.log(`Auth failure for ${ip}: ${attempts.failures}/${MAX_AUTH_FAILURES}`);
}

function resetAuthFailures(ip) {
  connectionAttempts.delete(ip);
}

function generateHmacSignature(payload, secret) {
  return crypto.createHmac('sha256', secret).update(JSON.stringify(payload)).digest('hex');
}

// Create SMTP server options
const serverOptions = {
  // Server options
  banner: 'Email Sender SMTP Relay',
  size: 14680064, // 14MB max message size
  logger: true, // Log raw SMTP commands for debugging

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

  // Authentication configuration
  authOptional: !SMTP_AUTH_REQUIRED,
  authMethods: ['PLAIN', 'LOGIN'],

  // Handle incoming connections
  onConnect(session, callback) {
    const ip = session.remoteAddress;
    console.log(`[${session.id}] New connection from ${ip}`);

    // Check if IP is blocked due to too many auth failures
    if (isBlocked(ip)) {
      console.log(`[${session.id}] Connection rejected - IP blocked: ${ip}`);
      return callback(new Error('Too many authentication failures. Try again later.'));
    }

    return callback(); // Accept connection
  },

  // Handle authentication (async via API)
  async onAuth(auth, session, callback) {
    const ip = session.remoteAddress;
    console.log(`[${session.id}] Auth attempt: ${auth.username} from ${ip}`);

    // Check if IP is blocked
    if (isBlocked(ip)) {
      return callback(new Error('Too many authentication failures'));
    }

    // Validate credentials via API (against SmtpCredential model in Dashboard)
    try {
      const result = await authenticateViaAPI(auth.username, auth.password);

      if (result.success) {
        console.log(`[${session.id}] Auth successful for ${auth.username} (rate_limit: ${result.rateLimit})`);
        resetAuthFailures(ip);
        return callback(null, {
          user: result.username,
          rateLimit: result.rateLimit
        });
      }

      console.log(`[${session.id}] Auth failed for ${auth.username}: ${result.error}`);
      recordAuthFailure(ip);
      return callback(new Error(result.error || 'Invalid username or password'));
    } catch (error) {
      console.error(`[${session.id}] Auth error:`, error.message);
      recordAuthFailure(ip);
      return callback(new Error('Authentication failed'));
    }
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
        console.log(`  Subject: ${email.subject}`)

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
    const timestamp = Date.now().toString();

    // Convert headers from Map to plain object (mailparser returns Map,
    // which JSON.stringify serializes as "{}" losing all headers)
    const headersObj = {};
    if (parsed.headers) {
      for (const [key, value] of parsed.headers) {
        headersObj[key.toLowerCase()] = value;
      }
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
      raw: raw.toString('base64'),
      timestamp: timestamp
    };

    // Build request headers
    const headers = {
      'Content-Type': 'application/json',
      'X-SMTP-Relay-Timestamp': timestamp
    };

    // Add HMAC signature if secret is configured
    if (SMTP_RELAY_SECRET) {
      const signature = generateHmacSignature(payload, SMTP_RELAY_SECRET);
      headers['X-SMTP-Relay-Signature'] = signature;
      console.log(`[${session.id}] Request signed with HMAC`);
    }

    const response = await axios.post(`${API_URL}/api/v1/smtp/receive`, payload, {
      headers: headers,
      timeout: 30000
    });

    console.log(`API response:`, response.status, response.data);
  } catch (error) {
    console.error('Failed to forward to API:', error.message);
    if (error.response) {
      console.error('Response status:', error.response.status);
      console.error('Response data:', error.response.data);
    }
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
