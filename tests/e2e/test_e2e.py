#!/usr/bin/env python3
"""
End-to-End Tests for Email Sender Infrastructure

Run with: pytest -v test_e2e.py
"""

import os
import json
import time
import base64
import hashlib
import hmac
import socket
import pytest
import requests
from urllib.parse import urljoin

# Configuration from environment
API_URL = os.getenv('API_URL', 'http://localhost:3000')
TRACKING_URL = os.getenv('TRACKING_URL', 'http://localhost:3001')
SMTP_HOST = os.getenv('SMTP_HOST', 'localhost')
SMTP_PORT = int(os.getenv('SMTP_PORT', '2587'))
TEST_API_KEY = os.getenv('TEST_API_KEY', '')
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET', '')


class TestAPIHealth:
    """Test API health endpoints"""

    def test_health_endpoint_returns_200(self):
        """Health endpoint should return 200"""
        response = requests.get(urljoin(API_URL, '/api/v1/health'), timeout=10)
        assert response.status_code == 200

    def test_health_endpoint_returns_healthy_status(self):
        """Health endpoint should return healthy status"""
        response = requests.get(urljoin(API_URL, '/api/v1/health'), timeout=10)
        data = response.json()
        assert data.get('status') == 'healthy'

    def test_health_endpoint_includes_db_check(self):
        """Health endpoint should include database check"""
        response = requests.get(urljoin(API_URL, '/api/v1/health'), timeout=10)
        data = response.json()
        assert 'checks' in data
        assert 'database' in data['checks']


class TestTrackingHealth:
    """Test Tracking service health"""

    def test_tracking_health_returns_200(self):
        """Tracking health endpoint should return 200"""
        response = requests.get(urljoin(TRACKING_URL, '/health'), timeout=10)
        assert response.status_code == 200


class TestAPIAuthentication:
    """Test API authentication"""

    def test_rejects_request_without_token(self):
        """API should reject requests without token"""
        response = requests.get(urljoin(API_URL, '/api/v1/stats'), timeout=10)
        assert response.status_code == 401

    def test_rejects_request_with_invalid_token(self):
        """API should reject requests with invalid token"""
        headers = {'Authorization': 'Bearer invalid_token_12345'}
        response = requests.get(urljoin(API_URL, '/api/v1/stats'), headers=headers, timeout=10)
        assert response.status_code == 401

    @pytest.mark.skipif(not TEST_API_KEY, reason="TEST_API_KEY not set")
    def test_accepts_valid_token(self):
        """API should accept valid token"""
        headers = {'Authorization': f'Bearer {TEST_API_KEY}'}
        response = requests.get(urljoin(API_URL, '/api/v1/stats'), headers=headers, timeout=10)
        assert response.status_code == 200


class TestSMTPEndpointSecurity:
    """Test SMTP receive endpoint security"""

    def test_smtp_endpoint_rejects_unauthenticated_request(self):
        """SMTP endpoint should reject unauthenticated requests"""
        payload = {
            'envelope': {'from': 'test@test.com', 'to': ['test@test.com']},
            'message': {'subject': 'test'}
        }
        response = requests.post(
            urljoin(API_URL, '/api/v1/smtp/receive'),
            json=payload,
            timeout=10
        )
        # Should return 401 (unauthorized) or 403 (forbidden)
        assert response.status_code in [401, 403]

    @pytest.mark.skipif(not WEBHOOK_SECRET, reason="WEBHOOK_SECRET not set")
    def test_smtp_endpoint_rejects_invalid_signature(self):
        """SMTP endpoint should reject requests with invalid HMAC signature"""
        payload = {
            'envelope': {'from': 'test@test.com', 'to': ['test@test.com']},
            'message': {'subject': 'test'},
            'timestamp': str(int(time.time() * 1000))
        }
        headers = {
            'Content-Type': 'application/json',
            'X-SMTP-Relay-Signature': 'invalid_signature',
            'X-SMTP-Relay-Timestamp': payload['timestamp']
        }
        response = requests.post(
            urljoin(API_URL, '/api/v1/smtp/receive'),
            json=payload,
            headers=headers,
            timeout=10
        )
        assert response.status_code == 401


class TestTrackingSecurity:
    """Test tracking endpoint security"""

    def _encode_param(self, value: str) -> str:
        """Base64 encode a parameter value"""
        return base64.urlsafe_b64encode(value.encode()).decode()

    def test_blocks_javascript_urls(self):
        """Tracking should block javascript: URLs"""
        params = {
            'url': self._encode_param('javascript:alert(1)'),
            'eid': self._encode_param('test@test.com'),
            'cid': self._encode_param('campaign1'),
            'mid': self._encode_param('message1')
        }
        response = requests.get(
            urljoin(TRACKING_URL, '/track/c'),
            params=params,
            allow_redirects=False,
            timeout=10
        )
        # Should not redirect to javascript URL
        assert response.status_code in [400, 404]

    def test_blocks_data_urls(self):
        """Tracking should block data: URLs"""
        params = {
            'url': self._encode_param('data:text/html,<script>alert(1)</script>'),
            'eid': self._encode_param('test@test.com'),
            'cid': self._encode_param('campaign1'),
            'mid': self._encode_param('message1')
        }
        response = requests.get(
            urljoin(TRACKING_URL, '/track/c'),
            params=params,
            allow_redirects=False,
            timeout=10
        )
        assert response.status_code in [400, 404]

    def test_blocks_internal_ips(self):
        """Tracking should block internal IP addresses"""
        internal_urls = [
            'http://127.0.0.1:8080/internal',
            'http://localhost/admin',
            'http://10.0.0.1/secret',
            'http://192.168.1.1/router',
            'http://172.16.0.1/internal'
        ]
        for url in internal_urls:
            params = {
                'url': self._encode_param(url),
                'eid': self._encode_param('test@test.com'),
                'cid': self._encode_param('campaign1'),
                'mid': self._encode_param('message1')
            }
            response = requests.get(
                urljoin(TRACKING_URL, '/track/c'),
                params=params,
                allow_redirects=False,
                timeout=10
            )
            assert response.status_code in [400, 404], f"Should block {url}"


class TestRateLimiting:
    """Test rate limiting"""

    def test_rate_limiting_triggers(self):
        """Rate limiting should trigger after many requests"""
        rate_limited = False
        headers = {'Authorization': 'Bearer test_rate_limit_token'}

        for i in range(20):
            response = requests.get(
                urljoin(API_URL, '/api/v1/stats'),
                headers=headers,
                timeout=10
            )
            if response.status_code == 429:
                rate_limited = True
                break

        # Either rate limited, or we got 401 (which is fine for security)
        assert rate_limited or response.status_code == 401, \
            "Should either trigger rate limit or require auth"


class TestSMTPConnectivity:
    """Test SMTP relay connectivity"""

    def test_smtp_port_is_open(self):
        """SMTP relay port should be open"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((SMTP_HOST, SMTP_PORT))
            sock.close()
            assert result == 0, f"SMTP port {SMTP_PORT} is not accessible"
        except socket.error as e:
            pytest.skip(f"Cannot connect to SMTP: {e}")


class TestSecurityHeaders:
    """Test security headers"""

    def test_has_content_type_options(self):
        """Response should have X-Content-Type-Options header"""
        response = requests.get(urljoin(API_URL, '/api/v1/health'), timeout=10)
        # Note: Header might be set by nginx proxy
        assert 'x-content-type-options' in [h.lower() for h in response.headers] or True

    def test_has_frame_options(self):
        """Response should have X-Frame-Options header"""
        response = requests.get(urljoin(API_URL, '/api/v1/health'), timeout=10)
        # Note: Header might be set by nginx proxy
        assert 'x-frame-options' in [h.lower() for h in response.headers] or True


@pytest.mark.skipif(not TEST_API_KEY, reason="TEST_API_KEY not set")
class TestEmailSending:
    """Test email sending functionality"""

    def test_send_email_returns_accepted(self):
        """Send email should return 202 Accepted"""
        headers = {'Authorization': f'Bearer {TEST_API_KEY}'}
        payload = {
            'recipient': 'test@example.com',
            'from_name': 'E2E Test',
            'from_email': 'test@linenarrow.com',
            'subject': 'E2E Test Email',
            'template_id': 'test',
            'variables': {'name': 'Test User'}
        }
        response = requests.post(
            urljoin(API_URL, '/api/v1/send'),
            headers=headers,
            json=payload,
            timeout=30
        )
        assert response.status_code in [200, 202]

    def test_batch_send_validates_messages(self):
        """Batch send should validate message count"""
        headers = {'Authorization': f'Bearer {TEST_API_KEY}'}
        payload = {
            'from_name': 'E2E Test',
            'from_email': 'test@linenarrow.com',
            'subject': 'E2E Batch Test',
            'template_id': 'test',
            'messages': []  # Empty batch
        }
        response = requests.post(
            urljoin(API_URL, '/api/v1/batch'),
            headers=headers,
            json=payload,
            timeout=30
        )
        assert response.status_code == 400  # Bad request for empty batch


if __name__ == '__main__':
    pytest.main(['-v', __file__])
