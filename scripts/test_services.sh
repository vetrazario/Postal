#!/bin/bash
# ===========================================
# Тестирование сервисов: трекинг, отписка, вебхуки
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

cd /opt/email-sender

DOMAIN="${DOMAIN:-linenarrow.com}"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Тестирование сервисов (домен: $DOMAIN)${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# --- 1. Проверка контейнеров ---
echo -e "${YELLOW}1. Статус контейнеров:${NC}"
for svc in api tracking nginx redis postgres; do
    status=$(docker compose ps --format '{{.Status}}' $svc 2>/dev/null | head -1)
    if echo "$status" | grep -q "Up"; then
        echo -e "   ${GREEN}✓${NC} $svc: $status"
    else
        echo -e "   ${RED}✗${NC} $svc: $status"
    fi
done
echo ""

# --- 2. Health check API ---
echo -e "${YELLOW}2. API Health:${NC}"
health=$(curl -sk "https://$DOMAIN/api/v1/health" 2>/dev/null || echo "FAIL")
if echo "$health" | grep -q "healthy"; then
    echo -e "   ${GREEN}✓${NC} API healthy"
else
    echo -e "   ${RED}✗${NC} API: $health"
fi
echo ""

# --- 3. Тест Tracking Open (pixel) ---
echo -e "${YELLOW}3. Tracking Open (/track/o):${NC}"
# Тестовые параметры
test_eid=$(echo -n "test@example.com" | base64 -w0)
test_cid=$(echo -n "test_campaign" | base64 -w0)
test_mid=$(echo -n "test_message_123" | base64 -w0)

response=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/track/o?eid=$test_eid&cid=$test_cid&mid=$test_mid" 2>/dev/null || echo "000")
if [ "$response" = "200" ] || [ "$response" = "404" ]; then
    # 404 OK - message not found in DB, but service works
    echo -e "   ${GREEN}✓${NC} Tracking service responds (HTTP $response)"
else
    echo -e "   ${RED}✗${NC} Tracking service error (HTTP $response)"
    echo "   Проверь: docker compose logs tracking --tail=20"
fi
echo ""

# --- 4. Тест Tracking Click ---
echo -e "${YELLOW}4. Tracking Click (/track/c):${NC}"
test_url=$(echo -n "https://example.com" | base64 -w0)
response=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/track/c?url=$test_url&eid=$test_eid&cid=$test_cid&mid=$test_mid" 2>/dev/null || echo "000")
if [ "$response" = "302" ] || [ "$response" = "200" ] || [ "$response" = "404" ]; then
    echo -e "   ${GREEN}✓${NC} Click tracking responds (HTTP $response)"
else
    echo -e "   ${RED}✗${NC} Click tracking error (HTTP $response)"
    echo "   Проверь: docker compose logs tracking --tail=20"
fi
echo ""

# --- 5. Тест Unsubscribe страницы ---
echo -e "${YELLOW}5. Unsubscribe Page (/unsubscribe):${NC}"
response=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/unsubscribe?eid=$test_eid&cid=$test_cid" 2>/dev/null || echo "000")
if [ "$response" = "200" ]; then
    echo -e "   ${GREEN}✓${NC} Unsubscribe page works (HTTP $response)"
else
    echo -e "   ${RED}✗${NC} Unsubscribe page error (HTTP $response)"
    # Показать что возвращает
    echo "   Ответ сервера:"
    curl -sk "https://$DOMAIN/unsubscribe?eid=$test_eid&cid=$test_cid" 2>/dev/null | head -20
    echo ""
    echo "   Проверь логи: docker compose logs api --tail=30"
fi
echo ""

# --- 6. Тест реальной ссылки отписки (если передана) ---
if [ -n "$1" ]; then
    echo -e "${YELLOW}6. Тест переданной ссылки:${NC}"
    echo "   URL: $1"
    response=$(curl -sk -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000")
    echo "   HTTP: $response"
    if [ "$response" != "200" ]; then
        echo "   Ответ:"
        curl -sk "$1" 2>/dev/null | head -30
    fi
    echo ""
fi

# --- 7. Логи ошибок ---
echo -e "${YELLOW}7. Последние ошибки в логах:${NC}"
echo "   API:"
docker compose logs api --tail=50 2>/dev/null | grep -iE "(error|exception|fail)" | tail -5 || echo "   (нет ошибок)"
echo ""
echo "   Tracking:"
docker compose logs tracking --tail=50 2>/dev/null | grep -iE "(error|exception|fail)" | tail -5 || echo "   (нет ошибок)"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Диагностика завершена${NC}"
echo ""
