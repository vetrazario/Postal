#!/usr/bin/env node

/**
 * SMTP Relay Server for Email Sender Infrastructure
 *
 * This server accepts SMTP connections from AMS Enterprise,
 * parses emails, rebuilds headers to hide AMS traces,
 * injects tracking, and forwards to Rails API.
 */

const path = require('path');
const Haraka = require('Haraka');

// Load environment variables
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

// Haraka configuration
const server = new Haraka.Server({
  config_dir: path.join(__dirname, 'config')
});

// Log startup
console.log('=' .repeat(60));
console.log('Starting SMTP Relay Server');
console.log('=' .repeat(60));
console.log('Port:', process.env.SMTP_RELAY_PORT || 587);
console.log('TLS:', process.env.SMTP_RELAY_TLS || 'enabled');
console.log('Auth:', process.env.SMTP_RELAY_AUTH_REQUIRED || 'required');
console.log('API URL:', process.env.API_URL || 'http://api:3000');
console.log('=' .repeat(60));

// Start server
server.start(function() {
  console.log('✓ SMTP Relay Server started successfully');
  console.log(`✓ Listening on port ${process.env.SMTP_RELAY_PORT || 587}`);
});

// Handle shutdown gracefully
process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  server.stop();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('Received SIGINT, shutting down gracefully...');
  server.stop();
  process.exit(0);
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
  // Don't exit - log and continue
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit - log and continue
});
