#!/bin/bash
# Скрипт для автоматического исправления docker-compose.yml на сервере
# Убирает монтирование postal.yml

set -e

echo "🔧 Исправление docker-compose.yml..."

cd /opt/email-sender

# Создать backup
cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Создан backup: docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"

# Убрать строки с postal.yml
sed -i '/\.\/config\/postal\.yml:/d' docker-compose.yml

# Проверить что строки убраны
if grep -q "postal.yml" docker-compose.yml; then
    echo "❌ Ошибка: строки с postal.yml все еще присутствуют!"
    echo "Нужно исправить вручную"
    exit 1
else
    echo "✅ Строки с postal.yml успешно удалены из docker-compose.yml"
fi

echo ""
echo "✅ Готово! Теперь перезапустите Postal:"
echo "   docker compose restart postal"
