#!/bin/bash
set -e

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ФОРСИРОВАННОЕ ОБНОВЛЕНИЕ API                         ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

# 1. Git pull
echo "📥 1/6 - Подтягиваю код..."
git fetch origin claude/project-analysis-errors-Awt4F
git reset --hard origin/claude/project-analysis-errors-Awt4F

# 2. Проверка файла
echo ""
echo "🔍 2/6 - Проверяю что в коде есть Tracking карточка..."
if grep -q "Tracking Settings" services/api/app/views/dashboard/settings/show.html.erb; then
    echo "✅ Tracking карточка найдена в исходном коде"
else
    echo "❌ ОШИБКА: Tracking карточки нет в коде!"
    exit 1
fi

# 3. Остановка API
echo ""
echo "⏸️  3/6 - Останавливаю API контейнер..."
docker compose stop api

# 4. Удаление контейнера
echo ""
echo "🗑️  4/6 - Удаляю старый контейнер полностью..."
docker compose rm -f api

# 5. Пересборка с нуля
echo ""
echo "🔨 5/6 - Пересобираю API с нуля (без кэша)..."
docker compose build --no-cache api

# 6. Запуск
echo ""
echo "🚀 6/6 - Запускаю новый контейнер..."
docker compose up -d api

echo ""
echo "⏳ Жду 15 секунд пока API запустится..."
sleep 15

echo ""
echo "📊 Статус:"
docker compose ps api

echo ""
echo "📝 Последние 20 строк лога API:"
docker compose logs api --tail=20

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ✅ ГОТОВО!                                            ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Теперь ОБНОВИ страницу в браузере (Ctrl+Shift+R):"
echo "  👉 https://linenarrow.com/dashboard/settings"
echo ""
echo "Должна появиться 4-я карточка 'Tracking' с кнопкой"
echo "'Tracking Settings' внизу карточки."
echo ""
echo "Если все равно не появилась, очисти кэш браузера полностью."
echo ""
