#!/bin/bash
# ===========================================
# End-to-End Test Runner
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
PASSED=0
FAILED=0
SKIPPED=0

# Configuration
API_URL="${API_URL:-http://localhost:3000}"
TRACKING_URL="${TRACKING_URL:-http://localhost:3001}"
SMTP_HOST="${SMTP_HOST:-localhost}"
SMTP_PORT="${SMTP_PORT:-2587}"
TEST_API_KEY="${TEST_API_KEY:-}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; ((SKIPPED++)); }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check curl
    if command -v curl &> /dev/null; then
        log_pass "curl is installed"
    else
        log_fail "curl is not installed"
        exit 1
    fi

    # Check jq
    if command -v jq &> /dev/null; then
        log_pass "jq is installed"
    else
        log_fail "jq is not installed"
        exit 1
    fi

    # Check nc (netcat)
    if command -v nc &> /dev/null; then
        log_pass "netcat is installed"
    else
        log_skip "netcat not installed - SMTP tests will be skipped"
    fi
}

# Test API Health
test_api_health() {
    log_section "Testing API Health"

    response=$(curl -s -w "\n%{http_code}" "$API_URL/api/v1/health" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "200" ]; then
        status=$(echo "$body" | jq -r '.status' 2>/dev/null || echo "unknown")
        if [ "$status" = "healthy" ]; then
            log_pass "API health check passed (status: $status)"
        else
            log_fail "API health check returned non-healthy status: $status"
        fi
    else
        log_fail "API health check failed (HTTP $http_code)"
    fi
}

# Test Tracking Health
test_tracking_health() {
    log_section "Testing Tracking Service Health"

    response=$(curl -s -w "\n%{http_code}" "$TRACKING_URL/health" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        log_pass "Tracking service health check passed"
    else
        log_fail "Tracking service health check failed (HTTP $http_code)"
    fi
}

# Test API Authentication
test_api_authentication() {
    log_section "Testing API Authentication"

    # Test without token
    response=$(curl -s -w "\n%{http_code}" "$API_URL/api/v1/stats" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "401" ]; then
        log_pass "API correctly rejects requests without token"
    else
        log_fail "API should reject requests without token (got HTTP $http_code)"
    fi

    # Test with invalid token
    response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer invalid_token" "$API_URL/api/v1/stats" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "401" ]; then
        log_pass "API correctly rejects invalid tokens"
    else
        log_fail "API should reject invalid tokens (got HTTP $http_code)"
    fi

    # Test with valid token (if provided)
    if [ -n "$TEST_API_KEY" ]; then
        response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TEST_API_KEY" "$API_URL/api/v1/stats" 2>/dev/null || echo "error")
        http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" = "200" ]; then
            log_pass "API accepts valid token"
        else
            log_fail "API should accept valid token (got HTTP $http_code)"
        fi
    else
        log_skip "Valid token test skipped (TEST_API_KEY not set)"
    fi
}

# Test Rate Limiting
test_rate_limiting() {
    log_section "Testing Rate Limiting"

    # Make 15 rapid requests to trigger rate limit
    success_count=0
    rate_limited=false

    for i in $(seq 1 15); do
        response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer test_token" "$API_URL/api/v1/stats" 2>/dev/null)
        http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" = "429" ]; then
            rate_limited=true
            break
        fi
        ((success_count++))
    done

    if [ "$rate_limited" = true ]; then
        log_pass "Rate limiting is working (triggered after $success_count requests)"
    else
        log_skip "Rate limiting not triggered in 15 requests (may need more requests)"
    fi
}

# Test SMTP Relay Connectivity
test_smtp_connectivity() {
    log_section "Testing SMTP Relay"

    if ! command -v nc &> /dev/null; then
        log_skip "SMTP test skipped (netcat not installed)"
        return
    fi

    # Test SMTP port is open
    if nc -z -w5 "$SMTP_HOST" "$SMTP_PORT" 2>/dev/null; then
        log_pass "SMTP relay port is open ($SMTP_HOST:$SMTP_PORT)"
    else
        log_fail "SMTP relay port is not accessible ($SMTP_HOST:$SMTP_PORT)"
    fi
}

# Test SMTP Receive Endpoint Security
test_smtp_endpoint_security() {
    log_section "Testing SMTP Endpoint Security"

    # Test without signature from external IP
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"envelope":{"from":"test@test.com","to":["test@test.com"]},"message":{"subject":"test"}}' \
        "$API_URL/api/v1/smtp/receive" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        log_pass "SMTP endpoint correctly rejects unauthenticated requests"
    else
        log_fail "SMTP endpoint should reject unauthenticated requests (got HTTP $http_code)"
    fi
}

# Test Tracking Open Redirect Prevention
test_tracking_security() {
    log_section "Testing Tracking Security"

    # Test open redirect prevention
    evil_url=$(echo -n "javascript:alert(1)" | base64 -w0)
    eid=$(echo -n "test@test.com" | base64 -w0)
    cid=$(echo -n "campaign1" | base64 -w0)
    mid=$(echo -n "message1" | base64 -w0)

    response=$(curl -s -w "\n%{http_code}" -L --max-redirs 0 \
        "$TRACKING_URL/track/c?url=$evil_url&eid=$eid&cid=$cid&mid=$mid" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "404" ] || [ "$http_code" = "400" ]; then
        log_pass "Tracking correctly blocks javascript: URLs"
    else
        log_fail "Tracking should block javascript: URLs (got HTTP $http_code)"
    fi

    # Test internal IP blocking
    internal_url=$(echo -n "http://127.0.0.1:8080/internal" | base64 -w0)

    response=$(curl -s -w "\n%{http_code}" -L --max-redirs 0 \
        "$TRACKING_URL/track/c?url=$internal_url&eid=$eid&cid=$cid&mid=$mid" 2>/dev/null || echo "error")
    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "404" ] || [ "$http_code" = "400" ]; then
        log_pass "Tracking correctly blocks internal IPs"
    else
        log_fail "Tracking should block internal IPs (got HTTP $http_code)"
    fi
}

# Test Security Headers
test_security_headers() {
    log_section "Testing Security Headers"

    headers=$(curl -s -I "$API_URL/api/v1/health" 2>/dev/null)

    # Check HSTS
    if echo "$headers" | grep -qi "strict-transport-security"; then
        log_pass "HSTS header is present"
    else
        log_skip "HSTS header not found (may be behind reverse proxy)"
    fi

    # Check X-Content-Type-Options
    if echo "$headers" | grep -qi "x-content-type-options"; then
        log_pass "X-Content-Type-Options header is present"
    else
        log_fail "X-Content-Type-Options header is missing"
    fi

    # Check X-Frame-Options
    if echo "$headers" | grep -qi "x-frame-options"; then
        log_pass "X-Frame-Options header is present"
    else
        log_fail "X-Frame-Options header is missing"
    fi
}

# Test Email Sending (if API key provided)
test_email_sending() {
    log_section "Testing Email Sending"

    if [ -z "$TEST_API_KEY" ]; then
        log_skip "Email sending test skipped (TEST_API_KEY not set)"
        return
    fi

    # Send test email
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $TEST_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "recipient": "test@example.com",
            "from_name": "E2E Test",
            "from_email": "test@linenarrow.com",
            "subject": "E2E Test Email",
            "template_id": "test",
            "variables": {"name": "Test User"}
        }' \
        "$API_URL/api/v1/send" 2>/dev/null || echo "error")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "202" ] || [ "$http_code" = "200" ]; then
        message_id=$(echo "$body" | jq -r '.message_id' 2>/dev/null || echo "")
        if [ -n "$message_id" ]; then
            log_pass "Email queued successfully (ID: $message_id)"
        else
            log_pass "Email accepted (no message ID returned)"
        fi
    else
        log_fail "Email sending failed (HTTP $http_code)"
    fi
}

# Print summary
print_summary() {
    log_section "Test Summary"
    echo -e "${GREEN}Passed:${NC}  $PASSED"
    echo -e "${RED}Failed:${NC}  $FAILED"
    echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
    echo ""

    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "  Email Sender E2E Test Suite"
    echo "=========================================="
    echo ""
    echo "API URL: $API_URL"
    echo "Tracking URL: $TRACKING_URL"
    echo "SMTP: $SMTP_HOST:$SMTP_PORT"
    echo ""

    check_prerequisites
    test_api_health
    test_tracking_health
    test_api_authentication
    test_rate_limiting
    test_smtp_connectivity
    test_smtp_endpoint_security
    test_tracking_security
    test_security_headers
    test_email_sending
    print_summary
}

main "$@"
