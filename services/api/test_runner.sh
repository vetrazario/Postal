#!/bin/bash
# Скрипт для запуска всех тестов и проверок

set -e

echo "=========================================="
echo "Запуск тестирования Email Sender API"
echo "=========================================="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода успеха
success() {
  echo -e "${GREEN}✓${NC} $1"
}

# Функция для вывода ошибки
error() {
  echo -e "${RED}✗${NC} $1"
}

# Функция для вывода предупреждения
warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# Проверка наличия необходимых переменных окружения
echo "1. Проверка переменных окружения..."
if [ -z "$DATABASE_URL" ]; then
  warning "DATABASE_URL не установлен, используем значение по умолчанию"
  export DATABASE_URL="postgres://email_sender:test_password@localhost:5432/email_sender_test"
fi

if [ -z "$REDIS_URL" ]; then
  warning "REDIS_URL не установлен, используем значение по умолчанию"
  export REDIS_URL="redis://localhost:6379/0"
fi

# Установка тестовых переменных, если не заданы
export RAILS_ENV=test
export SECRET_KEY_BASE=${SECRET_KEY_BASE:-test_secret_key_base_for_ci_1234567890123456789012345678901234567890123456789012345678901234}
export ENCRYPTION_PRIMARY_KEY=${ENCRYPTION_PRIMARY_KEY:-test_encryption_primary_key_32_chars}
export ENCRYPTION_DETERMINISTIC_KEY=${ENCRYPTION_DETERMINISTIC_KEY:-test_encryption_deterministic_key_32_chars}
export ENCRYPTION_KEY_DERIVATION_SALT=${ENCRYPTION_KEY_DERIVATION_SALT:-test_encryption_salt_32_chars}
export DASHBOARD_USERNAME=${DASHBOARD_USERNAME:-test_admin}
export DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD:-test_password}
export POSTAL_SIGNING_KEY=${POSTAL_SIGNING_KEY:-test_postal_signing_key_64_hex_chars_1234567890123456789012345678901234567890123456789012345678901234}
export POSTAL_WEBHOOK_PUBLIC_KEY=${POSTAL_WEBHOOK_PUBLIC_KEY:-test_public_key}
export CORS_ORIGINS=${CORS_ORIGINS:-http://localhost:3000}
export ALLOWED_SENDER_DOMAINS=${ALLOWED_SENDER_DOMAINS:-example.com}
export LOG_LEVEL=${LOG_LEVEL:-info}

echo ""
echo "2. Запуск RuboCop (проверка стиля кода)..."
if bundle exec rubocop; then
  success "RuboCop: все проверки пройдены"
else
  error "RuboCop: найдены проблемы со стилем кода"
  exit 1
fi

echo ""
echo "3. Запуск Brakeman (проверка безопасности)..."
if bundle exec brakeman --no-pager --quiet; then
  success "Brakeman: проблем безопасности не обнаружено"
else
  warning "Brakeman: обнаружены предупреждения (проверьте вывод выше)"
fi

echo ""
echo "4. Запуск RSpec тестов..."
if bundle exec rspec --format documentation; then
  success "RSpec: все тесты пройдены"
else
  error "RSpec: некоторые тесты не прошли"
  exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Все проверки завершены успешно!${NC}"
echo "=========================================="

