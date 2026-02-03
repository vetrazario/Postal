#!/bin/bash
# ===========================================
# Полная проверка и исправление системы
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Полная проверка и исправление системы"
echo "=========================================="
echo ""

# Шаг 1: Проверка кода
echo -e "${BLUE}[1/5] Проверка кода на сервере...${NC}"
if ! grep -q "class EmailParamsDto" services/api/app/dto/email_params_dto.rb 2>/dev/null; then
    echo -e "${RED}FAIL: Класс EmailParamsDto не найден. Выполните git pull origin main${NC}"
    exit 1
fi
echo -e "${GREEN}OK: Код актуален (EmailParamsDto)${NC}"
echo ""

# Шаг 2: Пересборка образов
echo -e "${BLUE}[2/5] Пересборка образов без кеша...${NC}"
docker compose build --no-cache api
echo -e "${GREEN}OK: Образ api пересобран${NC}"
echo ""

# Шаг 3: Остановка и пересоздание контейнеров
echo -e "${BLUE}[3/5] Остановка и пересоздание контейнеров...${NC}"
docker compose down
docker compose up -d
echo -e "${GREEN}OK: Контейнеры пересозданы${NC}"
echo ""

# Шаг 4: Ожидание запуска и проверка
echo -e "${BLUE}[4/5] Ожидание запуска сервисов (120 сек)...${NC}"
for i in {1..40}; do
    sleep 3
    echo -n "."
done
echo ""
echo -e "${GREEN}OK: Ожидание завершено${NC}"
echo ""

# Шаг 5: Проверка статуса
echo -e "${BLUE}[5/5] Проверка статуса сервисов...${NC}"
echo ""
docker compose ps
echo ""

# Детальная проверка
echo "=========================================="
echo "Детальная проверка компонентов"
echo "=========================================="
echo ""

# API
echo -e "${YELLOW}API:${NC}"
if docker compose ps api 2>/dev/null | grep -q "healthy"; then
    echo -e "${GREEN}  ✓ API healthy${NC}"
else
    echo -e "${RED}  ✗ API не healthy${NC}"
    docker compose logs api --tail=20
fi
echo ""

# Sidekiq
echo -e "${YELLOW}Sidekiq:${NC}"
if docker compose ps sidekiq 2>/dev/null | grep -q "Up"; then
    SIDEKIQ_ERRORS=$(docker compose logs sidekiq --tail=50 2>&1 | grep -c "EmailParamsDto.*but didn't" || true)
    if [ "${SIDEKIQ_ERRORS:-0}" -eq 0 ]; then
        echo -e "${GREEN}  ✓ Sidekiq работает без ошибок EmailParamsDto${NC}"
    else
        echo -e "${RED}  ✗ Sidekiq падает с ошибкой EmailParamsDto${NC}"
        docker compose logs sidekiq --tail=20
    fi
else
    echo -e "${RED}  ✗ Sidekiq не запущен${NC}"
fi
echo ""

# Postal
echo -e "${YELLOW}Postal:${NC}"
if docker compose ps postal 2>/dev/null | grep -q "Up"; then
    POSTAL_STATUS=$(docker compose ps postal | grep postal | awk '{print $5}')
    echo -e "  Status: ${POSTAL_STATUS}"
    if echo "$POSTAL_STATUS" | grep -q "healthy"; then
        echo -e "${GREEN}  ✓ Postal healthy${NC}"
    else
        echo -e "${YELLOW}  ⚠ Postal unhealthy (может требовать настройки через Web UI)${NC}"
    fi
else
    echo -e "${RED}  ✗ Postal не запущен${NC}"
fi
echo ""

# PostgreSQL
echo -e "${YELLOW}PostgreSQL:${NC}"
if docker compose exec -T postgres pg_isready -U email_sender 2>/dev/null | grep -q "accepting"; then
    echo -e "${GREEN}  ✓ PostgreSQL ready${NC}"
else
    echo -e "${RED}  ✗ PostgreSQL недоступен${NC}"
fi
echo ""

# Redis
echo -e "${YELLOW}Redis:${NC}"
if docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo -e "${GREEN}  ✓ Redis ready${NC}"
else
    echo -e "${RED}  ✗ Redis недоступен${NC}"
fi
echo ""

# Tracking
echo -e "${YELLOW}Tracking:${NC}"
if docker compose ps tracking 2>/dev/null | grep -q "healthy"; then
    echo -e "${GREEN}  ✓ Tracking healthy${NC}"
else
    echo -e "${RED}  ✗ Tracking не healthy${NC}"
fi
echo ""

# SMTP Relay
echo -e "${YELLOW}SMTP Relay:${NC}"
if docker compose ps smtp-relay 2>/dev/null | grep -q "healthy"; then
    echo -e "${GREEN}  ✓ SMTP Relay healthy${NC}"
else
    echo -e "${RED}  ✗ SMTP Relay не healthy${NC}"
fi
echo ""

echo "=========================================="
echo "Итоговая сводка"
echo "=========================================="
echo ""
echo "Выполните для детального просмотра:"
echo "  docker compose ps"
echo "  docker compose logs sidekiq -f"
echo "  docker compose logs api -f"
echo "  docker compose logs postal --tail=100"
echo ""
echo "Если Sidekiq или API падают, проверьте логи:"
echo "  docker compose logs sidekiq --tail=100"
echo "  docker compose logs api --tail=100"
echo ""
echo "Postal unhealthy — это нормально до первой настройки."
echo "Настройте Postal через Web UI: http://ваш_домен:5000"
echo ""
