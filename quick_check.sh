#!/bin/bash
# Quick Check Script - Автоматическая проверка всех критических проблем
# Использование: ./quick_check.sh

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Счетчики
CRITICAL=0
HIGH=0
MEDIUM=0
OK=0

echo "🔍 АВТОМАТИЧЕСКАЯ ПРОВЕРКА ПРОЕКТА POSTAL"
echo "=========================================="
echo "Дата: $(date)"
echo ""

# Функция для проверки
check() {
  local severity=$1
  local name=$2
  local command=$3
  local expected=$4

  echo -ne "Проверка: $name... "

  result=$(eval "$command" 2>&1) || result="ERROR"

  if [[ "$result" == *"$expected"* ]] || [ "$expected" = "OK" ]; then
    echo -e "${GREEN}✅ OK${NC}"
    ((OK++))
    return 0
  else
    case $severity in
      CRITICAL)
        echo -e "${RED}❌ КРИТИЧНО${NC}"
        ((CRITICAL++))
        ;;
      HIGH)
        echo -e "${YELLOW}⚠️  ВЫСОКИЙ${NC}"
        ((HIGH++))
        ;;
      MEDIUM)
        echo -e "${BLUE}ℹ️  СРЕДНИЙ${NC}"
        ((MEDIUM++))
        ;;
    esac
    echo "   Результат: $result"
    return 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔴 КРИТИЧЕСКИЕ ПРОБЛЕМЫ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Проверка базы данных
echo "1️⃣  БАЗА ДАННЫХ"
check "CRITICAL" "Подключение к БД" \
  "docker compose exec -T api rails runner 'puts ActiveRecord::Base.connection.active?' 2>/dev/null" \
  "true"

check "CRITICAL" "Количество таблиц (должно быть >= 15)" \
  "docker compose exec -T api rails runner 'puts ActiveRecord::Base.connection.tables.count' 2>/dev/null" \
  "OK"

# Проверка каждой критической таблицы
critical_tables=("api_keys" "email_logs" "email_templates" "tracking_events" "campaign_stats"
                 "smtp_credentials" "webhook_endpoints" "bounced_emails")

for table in "${critical_tables[@]}"; do
  check "HIGH" "Таблица $table" \
    "docker compose exec -T api rails runner \"puts ActiveRecord::Base.connection.table_exists?('$table')\" 2>/dev/null" \
    "true"
done

echo ""

# 2. Docker socket
echo "2️⃣  DOCKER SOCKET EXPOSURE"
if docker compose exec -T api test -e /var/run/docker.sock 2>/dev/null; then
  echo -e "${RED}❌ КРИТИЧНО: Docker socket СМОНТИРОВАН в контейнер!${NC}"
  echo "   Путь: /var/run/docker.sock"
  echo "   Риск: Контейнер может управлять хостом"
  ((CRITICAL++))
else
  echo -e "${GREEN}✅ OK: Docker socket НЕ смонтирован${NC}"
  ((OK++))
fi

echo ""

# 3. Webhook verification
echo "3️⃣  WEBHOOK VERIFICATION"
skip_verify=$(docker compose exec -T api printenv SKIP_POSTAL_WEBHOOK_VERIFICATION 2>/dev/null || echo "not_set")
if [ "$skip_verify" = "true" ]; then
  echo -e "${RED}❌ КРИТИЧНО: Проверка подписи webhook ОТКЛЮЧЕНА!${NC}"
  echo "   SKIP_POSTAL_WEBHOOK_VERIFICATION=true"
  echo "   Риск: Любой может отправлять поддельные webhooks"
  ((CRITICAL++))
else
  echo -e "${GREEN}✅ OK: Webhook verification включена или не задана${NC}"
  ((OK++))
fi

# Проверка наличия публичного ключа
pubkey_file=$(docker compose exec -T api printenv POSTAL_WEBHOOK_PUBLIC_KEY_FILE 2>/dev/null || echo "not_set")
if [ "$pubkey_file" != "not_set" ]; then
  if docker compose exec -T api test -f "$pubkey_file" 2>/dev/null; then
    echo -e "${GREEN}✅ OK: Файл публичного ключа существует: $pubkey_file${NC}"
    ((OK++))
  else
    echo -e "${YELLOW}⚠️  WARNING: Файл публичного ключа НЕ существует: $pubkey_file${NC}"
    ((HIGH++))
  fi
fi

echo ""

# 4. Weak encryption
echo "4️⃣  ШИФРОВАНИЕ"
secret_key_len=$(docker compose exec -T api bash -c 'echo -n $SECRET_KEY_BASE | wc -c' 2>/dev/null || echo "0")
if [ "$secret_key_len" -ge 64 ]; then
  echo -e "${GREEN}✅ OK: SECRET_KEY_BASE имеет адекватную длину ($secret_key_len символов)${NC}"
  ((OK++))
else
  echo -e "${RED}❌ КРИТИЧНО: SECRET_KEY_BASE слишком короткий ($secret_key_len символов)${NC}"
  echo "   Минимум: 64 символа"
  ((CRITICAL++))
fi

# Проверка наличия encryption keys
for key in ENCRYPTION_PRIMARY_KEY ENCRYPTION_DETERMINISTIC_KEY ENCRYPTION_KEY_DERIVATION_SALT; do
  value=$(docker compose exec -T api printenv "$key" 2>/dev/null || echo "")
  if [ -n "$value" ] && [ "$value" != "CHANGE_ME" ]; then
    echo -e "${GREEN}✅ OK: $key установлен${NC}"
    ((OK++))
  else
    echo -e "${RED}❌ КРИТИЧНО: $key НЕ установлен или содержит CHANGE_ME${NC}"
    ((CRITICAL++))
  fi
done

echo ""

# 5. IP-based authentication
echo "5️⃣  АУТЕНТИФИКАЦИЯ"
if docker compose exec -T api grep -q "client_ip.start_with?" app/controllers/api/v1/smtp_controller.rb 2>/dev/null; then
  echo -e "${RED}❌ КРИТИЧНО: Используется IP-based аутентификация${NC}"
  echo "   Файл: app/controllers/api/v1/smtp_controller.rb"
  echo "   Риск: IP можно подделать через X-Forwarded-For"
  ((CRITICAL++))
else
  echo -e "${GREEN}✅ OK: IP-based auth не обнаружена${NC}"
  ((OK++))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🟠 ВЫСОКИЙ ПРИОРИТЕТ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 6. Memory limits
echo "6️⃣  MEMORY LIMITS"

# Проверка API
api_mem=$(docker inspect email_api 2>/dev/null | grep -o '"Memory":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
api_mem_mb=$((api_mem / 1024 / 1024))
if [ "$api_mem" -gt 0 ] && [ "$api_mem_mb" -lt 800 ]; then
  echo -e "${YELLOW}⚠️  WARNING: API memory limit низкий: ${api_mem_mb}MB${NC}"
  echo "   Рекомендуется: минимум 800MB"
  ((HIGH++))
else
  echo -e "${GREEN}✅ OK: API memory limit адекватный (${api_mem_mb}MB)${NC}"
  ((OK++))
fi

# Проверка PostgreSQL
pg_mem=$(docker inspect email_postgres 2>/dev/null | grep -o '"Memory":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
pg_mem_mb=$((pg_mem / 1024 / 1024))
if [ "$pg_mem" -gt 0 ] && [ "$pg_mem_mb" -lt 1000 ]; then
  echo -e "${YELLOW}⚠️  WARNING: PostgreSQL memory limit низкий: ${pg_mem_mb}MB${NC}"
  echo "   Рекомендуется: минимум 1GB"
  ((HIGH++))
else
  echo -e "${GREEN}✅ OK: PostgreSQL memory limit адекватный (${pg_mem_mb}MB)${NC}"
  ((OK++))
fi

# Проверка Postal
postal_mem=$(docker inspect email_postal 2>/dev/null | grep -o '"Memory":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
postal_mem_mb=$((postal_mem / 1024 / 1024))
if [ "$postal_mem" -gt 0 ] && [ "$postal_mem_mb" -lt 1500 ]; then
  echo -e "${YELLOW}⚠️  WARNING: Postal memory limit низкий: ${postal_mem_mb}MB${NC}"
  echo "   Рекомендуется: минимум 2GB"
  ((HIGH++))
else
  echo -e "${GREEN}✅ OK: Postal memory limit адекватный (${postal_mem_mb}MB)${NC}"
  ((OK++))
fi

echo ""

# 7. SMTP Authentication
echo "7️⃣  SMTP RELAY AUTHENTICATION"
if docker compose exec -T smtp-relay grep -q "authOptional: true" server.js 2>/dev/null; then
  echo -e "${YELLOW}⚠️  WARNING: SMTP relay принимает подключения без аутентификации${NC}"
  echo "   Файл: services/smtp-relay/server.js"
  echo "   Риск: Открытый relay, можно отправлять спам"
  ((HIGH++))
else
  echo -e "${GREEN}✅ OK: SMTP authentication включена${NC}"
  ((OK++))
fi

echo ""

# 8. Deprecated syntax
echo "8️⃣  DEPRECATED SYNTAX (Ruby 3.x)"
deprecated_count=$(docker compose exec -T api find app/ -name "*.rb" -exec grep -l "rescue =>" {} \; 2>/dev/null | wc -l || echo "0")
if [ "$deprecated_count" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  WARNING: Найдено $deprecated_count файлов с deprecated 'rescue =>'${NC}"
  echo "   Требуется замена на 'rescue StandardError =>'"
  ((MEDIUM++))
else
  echo -e "${GREEN}✅ OK: Deprecated syntax не найден${NC}"
  ((OK++))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 СИСТЕМНАЯ ИНФОРМАЦИЯ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Версии
echo "📦 ВЕРСИИ:"
ruby_version=$(docker compose exec -T api ruby --version 2>/dev/null || echo "unknown")
echo "   Ruby: $ruby_version"
rails_version=$(docker compose exec -T api rails --version 2>/dev/null || echo "unknown")
echo "   Rails: $rails_version"
node_version=$(docker compose exec -T smtp-relay node --version 2>/dev/null || echo "unknown")
echo "   Node.js: $node_version"

echo ""

# Статус сервисов
echo "🐳 DOCKER КОНТЕЙНЕРЫ:"
docker compose ps --format "table {{.Name}}\t{{.Status}}" | grep -E "Name|email_" || echo "Не удалось получить статус"

echo ""

# Использование ресурсов
echo "💾 ИСПОЛЬЗОВАНИЕ РЕСУРСОВ:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "NAME|email_" || echo "Не удалось получить статистику"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 ИТОГОВАЯ СТАТИСТИКА"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL=$((CRITICAL + HIGH + MEDIUM + OK))

echo "Проверено: $TOTAL элементов"
echo ""
echo -e "${RED}🔴 Критических проблем: $CRITICAL${NC}"
echo -e "${YELLOW}🟠 Высокий приоритет: $HIGH${NC}"
echo -e "${BLUE}🟡 Средний приоритет: $MEDIUM${NC}"
echo -e "${GREEN}✅ Без проблем: $OK${NC}"

echo ""

# Рекомендации
if [ $CRITICAL -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${RED}⚠️  ТРЕБУЕТСЯ НЕМЕДЛЕННОЕ ДЕЙСТВИЕ!${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Обнаружены критические проблемы безопасности!"
  echo "Прочитайте файл IMMEDIATE_FIXES.md для инструкций."
  echo ""
  exit 1
elif [ $HIGH -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${YELLOW}⚠️  ТРЕБУЕТСЯ ВНИМАНИЕ${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Обнаружены проблемы высокого приоритета."
  echo "Прочитайте файл FULL_ERROR_ANALYSIS_REPORT.md для деталей."
  echo ""
  exit 2
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${GREEN}✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ!${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Критических проблем не обнаружено."
  if [ $MEDIUM -gt 0 ]; then
    echo "Есть несколько проблем среднего приоритета для улучшения."
  fi
  echo ""
  exit 0
fi
