#!/bin/bash
set -e

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Деплой настроек трекинга                             ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# 1. Git pull
echo "📥 Подтягиваю последние изменения..."
git fetch origin claude/project-analysis-errors-Awt4F
git pull origin claude/project-analysis-errors-Awt4F

echo ""
echo "✅ Код обновлен"
echo ""

# 2. Проверка файлов
echo "🔍 Проверяю наличие файлов..."

FILES=(
  "services/api/app/controllers/dashboard/tracking_settings_controller.rb"
  "services/api/app/views/dashboard/tracking_settings/show.html.erb"
  "services/api/app/views/dashboard/settings/show.html.erb"
  "services/api/app/models/email_click.rb"
  "services/api/app/models/email_open.rb"
)

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✅ $file"
  else
    echo "  ❌ ОТСУТСТВУЕТ: $file"
    exit 1
  fi
done

echo ""
echo "✅ Все файлы на месте"
echo ""

# 3. Rebuild API
echo "🔨 Пересобираю API контейнер (это займет 1-2 минуты)..."
docker compose build api

echo ""
echo "✅ API пересобран"
echo ""

# 4. Restart
echo "🔄 Перезапускаю контейнеры..."
docker compose restart api sidekiq

echo ""
echo "⏳ Жду 10 секунд пока контейнеры запустятся..."
sleep 10

echo ""
echo "📊 Статус контейнеров:"
docker compose ps

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ✅ ГОТОВО!                                            ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Теперь открой в браузере:"
echo "  👉 https://linenarrow.com/dashboard/settings"
echo ""
echo "Там увидишь карточку 'Tracking' (4-я карточка)."
echo "Нажми на кнопку 'Tracking Settings' внутри этой карточки."
echo ""
echo "Если что-то не работает, проверь логи API:"
echo "  docker compose logs api -f"
echo ""
