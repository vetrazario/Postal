#!/bin/bash
# Безопасное исправление проблем #3 и #4
# НЕ трогает аутентификацию!

set -e

echo "════════════════════════════════════════════════════════"
echo "БЕЗОПАСНОЕ ИСПРАВЛЕНИЕ ПРОБЛЕМ"
echo "════════════════════════════════════════════════════════"
echo ""

# Создаем бэкапы
BACKUP_DIR="backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 Создание бэкапов..."
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml.bak"
cp -r services/api/app "$BACKUP_DIR/app_backup"
echo "✅ Бэкапы созданы в: $BACKUP_DIR"
echo ""

# ============================================================
# ПРОБЛЕМА #3: DOCKER SOCKET EXPOSURE
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ПРОБЛЕМА #3: Docker Socket Exposure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Что делаем:"
echo "  1. Удаляем /var/run/docker.sock из docker-compose.yml"
echo "  2. Комментируем функцию рестарта в settings_controller.rb"
echo ""

# Удаляем строку с docker.sock
if grep -q "/var/run/docker.sock" docker-compose.yml; then
  echo "Удаление docker socket из docker-compose.yml..."
  sed -i '/\/var\/run\/docker.sock/d' docker-compose.yml
  echo "✅ Docker socket удален"
else
  echo "ℹ️  Docker socket уже отсутствует"
fi

# Комментируем функцию restart в settings_controller
SETTINGS_FILE="services/api/app/controllers/dashboard/settings_controller.rb"

if [ -f "$SETTINGS_FILE" ]; then
  echo ""
  echo "Отключение функции рестарта сервисов..."

  # Добавляем предупреждение в начало метода restart_docker_service
  if grep -q "def restart_docker_service" "$SETTINGS_FILE"; then
    # Создаем временный файл с исправлениями
    cat > /tmp/settings_patch.txt << 'PATCH'
    # БЕЗОПАСНОСТЬ: Функция отключена - требовался Docker socket
    # Для рестарта используйте: docker compose restart <service>
    Rails.logger.warn "restart_docker_service called but disabled for security"
    return {
      service: service,
      success: false,
      error: "Function disabled: Docker socket removed for security. Use 'docker compose restart' manually."
    }

    # Оригинальный код закомментирован ниже:
    # docker_cmd = '/usr/bin/docker'
PATCH

    # Находим строку с def restart_docker_service и вставляем после нее
    sed -i '/def restart_docker_service(service)/a\    # БЕЗОПАСНОСТЬ: Функция отключена - требовался Docker socket\n    # Для рестарта используйте: docker compose restart <service>\n    Rails.logger.warn "restart_docker_service called but disabled for security"\n    return {\n      service: service,\n      success: false,\n      error: "Function disabled: Docker socket removed for security. Use '"'"'docker compose restart'"'"' manually."\n    }' "$SETTINGS_FILE"

    echo "✅ Функция рестарта отключена"
  else
    echo "ℹ️  Функция restart_docker_service не найдена"
  fi
else
  echo "⚠️  Файл settings_controller.rb не найден"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ПРОБЛЕМА #4: Deprecated Rescue Syntax"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Что делаем:"
echo "  Заменяем 'rescue =>' на 'rescue StandardError =>' во всех файлах"
echo ""

# Подсчитываем количество файлов
FILE_COUNT=$(find services/api/app -name "*.rb" -type f -exec grep -l "rescue =>" {} \; 2>/dev/null | wc -l)

echo "Найдено файлов с deprecated syntax: $FILE_COUNT"
echo ""

if [ "$FILE_COUNT" -gt 0 ]; then
  echo "Исправление файлов..."

  # Исправляем все файлы
  find services/api/app -name "*.rb" -type f -exec sed -i 's/rescue =>/rescue StandardError =>/g' {} \;

  echo "✅ Исправлено файлов: $FILE_COUNT"

  # Показываем примеры изменений
  echo ""
  echo "Примеры изменений:"
  find services/api/app -name "*.rb" -type f -exec grep -n "rescue StandardError =>" {} \; 2>/dev/null | head -5
else
  echo "ℹ️  Файлы с deprecated syntax не найдены"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ ИСПРАВЛЕНИЯ ЗАВЕРШЕНЫ"
echo "════════════════════════════════════════════════════════"
echo ""

echo "📊 Что было сделано:"
echo "  ✅ Удален Docker socket из docker-compose.yml"
echo "  ✅ Отключена функция рестарта сервисов"
echo "  ✅ Исправлен deprecated rescue syntax в $FILE_COUNT файлах"
echo ""

echo "📦 Бэкапы сохранены в: $BACKUP_DIR"
echo ""

echo "🔍 Проверьте изменения:"
echo "  git diff docker-compose.yml"
echo "  git diff services/api/app/"
echo ""

echo "♻️  Для применения изменений:"
echo "  docker compose up -d --force-recreate api"
echo ""

echo "⏮️  Для отката:"
echo "  cp $BACKUP_DIR/docker-compose.yml.bak docker-compose.yml"
echo "  cp -r $BACKUP_DIR/app_backup/* services/api/app/"
echo ""

echo "════════════════════════════════════════════════════════"
