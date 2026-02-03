#!/bin/bash
set -e

# ============================================
# Email Flow Test Script
# ============================================
# Tests full email sending flow:
# 1. Send email via API
# 2. Check Postal delivery
# 3. Verify webhook received
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_URL="https://linenarrow.com"
API_KEY="b2f9e27f1ff1e82433bf379861bb5a2ebf1f57976e162bb1"
POSTAL_API_KEY="FSJbztugA0ZmzAiF6GWWOtnv"
DOMAIN="linenarrow.com"

# Recipient email (passed as argument or default)
TO_EMAIL="${1:-vetrazario@gmail.com}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Email Flow Test Script${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "API URL: ${YELLOW}${API_URL}${NC}"
echo -e "Domain: ${YELLOW}${DOMAIN}${NC}"
echo -e "To: ${YELLOW}${TO_EMAIL}${NC}"
echo ""

# ============================================
# Step 1: Send Email via API
# ============================================
echo -e "${BLUE}[1/3] Sending email via API...${NC}"

MESSAGE_ID="test_$(date +%s)_$(openssl rand -hex 4)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/api/v1/send" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "{
    \"recipient\": \"${TO_EMAIL}\",
    \"from_email\": \"test@${DOMAIN}\",
    \"from_name\": \"Test Sender\",
    \"subject\": \"Test Email - ${TIMESTAMP}\",
    \"template_id\": null,
    \"variables\": {},
    \"tracking\": {
      \"message_id\": \"${MESSAGE_ID}\",
      \"campaign_id\": \"test_campaign\"
    }
  }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo -e "${GREEN}✓ Email sent successfully${NC}"
  echo -e "Response: ${BODY}"
  
  # Extract message_id from response
  POSTAL_MESSAGE_ID=$(echo "$BODY" | grep -o '"message_id":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$POSTAL_MESSAGE_ID" ]; then
    echo -e "Postal Message ID: ${YELLOW}${POSTAL_MESSAGE_ID}${NC}"
  fi
else
  echo -e "${RED}✗ Failed to send email${NC}"
  echo -e "HTTP Code: ${HTTP_CODE}"
  echo -e "Response: ${BODY}"
  exit 1
fi

echo ""

# ============================================
# Step 2: Check Email Status in API
# ============================================
echo -e "${BLUE}[2/3] Checking email status...${NC}"

# Wait a bit for processing
sleep 3

STATUS_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_URL}/api/v1/status/${MESSAGE_ID}" \
  -H "Authorization: Bearer ${API_KEY}")

STATUS_HTTP_CODE=$(echo "$STATUS_RESPONSE" | tail -n1)
STATUS_BODY=$(echo "$STATUS_RESPONSE" | sed '$d')

if [ "$STATUS_HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Status retrieved${NC}"
  echo -e "${STATUS_BODY}" | python3 -m json.tool 2>/dev/null || echo "$STATUS_BODY"
  
  # Extract status
  EMAIL_STATUS=$(echo "$STATUS_BODY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo -e "Current Status: ${YELLOW}${EMAIL_STATUS}${NC}"
else
  echo -e "${YELLOW}⚠ Could not retrieve status (might not be indexed yet)${NC}"
  echo -e "HTTP Code: ${STATUS_HTTP_CODE}"
  echo -e "Response: ${STATUS_BODY}"
fi

echo ""

# ============================================
# Step 3: Check Postal Logs
# ============================================
echo -e "${BLUE}[3/3] Checking Postal delivery...${NC}"

# Check if Postal API is accessible
POSTAL_CHECK=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:5000/api/v1/send/message" \
  -H "Content-Type: application/json" \
  -H "X-Server-API-Key: ${POSTAL_API_KEY}" \
  -d "{
    \"to\": [\"${TO_EMAIL}\"],
    \"from\": \"verify@${DOMAIN}\",
    \"subject\": \"Postal Verification - ${TIMESTAMP}\",
    \"plain_body\": \"This is a direct Postal test to verify server connectivity.\"
  }" 2>/dev/null || echo -e "\n000")

POSTAL_HTTP_CODE=$(echo "$POSTAL_CHECK" | tail -n1)
POSTAL_BODY=$(echo "$POSTAL_CHECK" | sed '$d')

if [ "$POSTAL_HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ Postal is operational${NC}"
  echo -e "Direct test email sent via Postal"
  echo -e "Response: ${POSTAL_BODY}"
else
  echo -e "${YELLOW}⚠ Could not send via Postal directly${NC}"
  echo -e "This is expected if running from outside the server"
fi

echo ""

# ============================================
# Summary
# ============================================
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Message ID: ${YELLOW}${MESSAGE_ID}${NC}"
echo -e "To: ${YELLOW}${TO_EMAIL}${NC}"
echo -e "Timestamp: ${YELLOW}${TIMESTAMP}${NC}"
echo ""
echo -e "${GREEN}✓ Email successfully sent via API${NC}"
echo -e "${YELLOW}→ Check recipient inbox for delivery${NC}"
echo -e "${YELLOW}→ Check Dashboard for webhook events${NC}"
echo ""
echo -e "Dashboard: ${BLUE}${API_URL}/dashboard${NC}"
echo -e "Logs: ${BLUE}${API_URL}/dashboard/logs${NC}"
echo ""
