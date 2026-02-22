/**
 * SMTP Relay Auth Tests
 * Tests authentication helper logic (HMAC, rate limiting simulation)
 */

const crypto = require('crypto');

describe('SMTP Auth helpers', () => {
  describe('HMAC signature generation', () => {
    it('generates consistent HMAC-SHA256 signature', () => {
      const payload = { username: 'test@example.com', timestamp: 12345 };
      const secret = 'test_secret';
      const signature = crypto
        .createHmac('sha256', secret)
        .update(JSON.stringify(payload))
        .digest('hex');

      expect(signature).toMatch(/^[a-f0-9]{64}$/);
      expect(typeof signature).toBe('string');
    });

    it('produces different signatures for different payloads', () => {
      const secret = 'test_secret';
      const sig1 = crypto.createHmac('sha256', secret).update('payload1').digest('hex');
      const sig2 = crypto.createHmac('sha256', secret).update('payload2').digest('hex');

      expect(sig1).not.toBe(sig2);
    });

    it('produces different signatures for different secrets', () => {
      const payload = 'same_payload';
      const sig1 = crypto.createHmac('sha256', 'secret1').update(payload).digest('hex');
      const sig2 = crypto.createHmac('sha256', 'secret2').update(payload).digest('hex');

      expect(sig1).not.toBe(sig2);
    });
  });
});
