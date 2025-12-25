/**
 * SMTP Authentication Plugin
 *
 * Authenticates SMTP connections against PostgreSQL database
 * Supports PLAIN and LOGIN authentication methods
 */

const { Pool } = require('pg');
const bcrypt = require('bcrypt');

// PostgreSQL connection pool
const pool = new Pool({
  connectionString: process.env.POSTGRES_URL ||
    `postgres://email_sender:${process.env.POSTGRES_PASSWORD}@postgres:5432/email_sender`
});

exports.register = function() {
  this.loginfo('SMTP Auth plugin loaded');
};

exports.hook_capabilities = function(next, connection) {
  // Only advertise AUTH after STARTTLS
  if (connection.tls.enabled) {
    const methods = ['PLAIN', 'LOGIN'];
    connection.capabilities.push(`AUTH ${methods.join(' ')}`);
    connection.notes.allowed_auth_methods = methods;
  }
  next();
};

exports.hook_unrecognized_command = function(next, connection, params) {
  // Handle AUTH command
  if (params[0] === 'AUTH' && params[1]) {
    return this.handle_auth(next, connection, params.slice(1));
  }
  next();
};

exports.handle_auth = async function(next, connection, params) {
  const method = params[0].toUpperCase();
  const plugin = this;

  if (!connection.tls.enabled) {
    return next(DENY, 'STARTTLS required before AUTH');
  }

  try {
    let username, password;

    if (method === 'PLAIN') {
      // AUTH PLAIN format: AUTH PLAIN base64(username\0username\0password)
      const credentials = params[1] ?
        Buffer.from(params[1], 'base64').toString('utf8').split('\0') :
        null;

      if (!credentials || credentials.length !== 3) {
        return next(DENY, 'Invalid AUTH PLAIN format');
      }

      username = credentials[1];
      password = credentials[2];

    } else if (method === 'LOGIN') {
      // AUTH LOGIN is interactive:
      // S: 334 VXNlcm5hbWU6 (base64 "Username:")
      // C: <base64 username>
      // S: 334 UGFzc3dvcmQ6 (base64 "Password:")
      // C: <base64 password>

      connection.respond(334, 'VXNlcm5hbWU6'); // "Username:"

      // Wait for username
      connection.pause();

      connection.on('line', function username_listener(line) {
        connection.removeListener('line', username_listener);
        username = Buffer.from(line, 'base64').toString('utf8');

        connection.respond(334, 'UGFzc3dvcmQ6'); // "Password:"

        connection.on('line', async function password_listener(line) {
          connection.removeListener('line', password_listener);
          password = Buffer.from(line, 'base64').toString('utf8');

          // Verify credentials
          const result = await plugin.verify_credentials(username, password);

          if (result.success) {
            connection.notes.auth_user = username;
            connection.notes.smtp_credential_id = result.credential_id;
            connection.relaying = true;

            // Update last_used_at
            await plugin.update_last_used(result.credential_id);

            plugin.loginfo(`Successful authentication: ${username}`);
            connection.respond(235, 'Authentication successful');
            connection.resume();
          } else {
            plugin.logwarn(`Failed authentication attempt: ${username}`);
            connection.respond(535, 'Authentication failed');
            connection.resume();
          }
        });

        connection.resume();
      });

      return; // Don't call next() - handled asynchronously
    } else {
      return next(DENY, `AUTH method ${method} not supported`);
    }

    // For PLAIN method, verify immediately
    if (method === 'PLAIN') {
      const result = await this.verify_credentials(username, password);

      if (result.success) {
        connection.notes.auth_user = username;
        connection.notes.smtp_credential_id = result.credential_id;
        connection.relaying = true;

        await this.update_last_used(result.credential_id);

        this.loginfo(`Successful authentication: ${username}`);
        return next(OK, 'Authentication successful');
      } else {
        this.logwarn(`Failed authentication attempt: ${username}`);
        return next(DENY, 'Authentication failed');
      }
    }

  } catch (error) {
    this.logerror(`Auth error: ${error.message}`);
    return next(DENYSOFT, 'Temporary authentication failure');
  }
};

exports.verify_credentials = async function(username, password) {
  try {
    const result = await pool.query(
      `SELECT id, username, password_hash, active, rate_limit
       FROM smtp_credentials
       WHERE username = $1 AND active = true`,
      [username]
    );

    if (result.rows.length === 0) {
      return { success: false };
    }

    const credential = result.rows[0];

    // Verify password using bcrypt
    const passwordMatch = await bcrypt.compare(password, credential.password_hash);

    if (passwordMatch) {
      return {
        success: true,
        credential_id: credential.id,
        username: credential.username,
        rate_limit: credential.rate_limit
      };
    } else {
      return { success: false };
    }

  } catch (error) {
    this.logerror(`Database error during auth: ${error.message}`);
    throw error;
  }
};

exports.update_last_used = async function(credential_id) {
  try {
    await pool.query(
      `UPDATE smtp_credentials SET last_used_at = NOW() WHERE id = $1`,
      [credential_id]
    );
  } catch (error) {
    this.logerror(`Error updating last_used_at: ${error.message}`);
  }
};

// Cleanup on shutdown
exports.shutdown = function() {
  pool.end();
};
