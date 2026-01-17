#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ПРИНУДИТЕЛЬНОЕ ОБНОВЛЕНИЕ (БЕЗ КЭША)                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1️⃣  Полная очистка локального кода"
echo "─────────────────────────────────────────────────────────────"
git fetch --all
git reset --hard origin/claude/project-analysis-errors-Awt4F
git clean -fd
echo "✅ Код полностью перезаписан из origin"

echo ""
echo "2️⃣  Проверка что фикс применен в коде"
echo "─────────────────────────────────────────────────────────────"
if grep -q "Events tracked" services/api/app/views/dashboard/settings/show.html.erb; then
  echo "❌ ОШИБКА: 'Events tracked' все еще в файле!"
  echo "Показываю что в файле:"
  grep -A 5 -B 5 "Events tracked" services/api/app/views/dashboard/settings/show.html.erb
  exit 1
else
  echo "✅ 'Events tracked' убран из кода"
fi

echo ""
echo "3️⃣  Остановка API"
echo "─────────────────────────────────────────────────────────────"
docker compose stop api

echo ""
echo "4️⃣  Удаление старого контейнера и образа"
echo "─────────────────────────────────────────────────────────────"
docker compose rm -f api
docker rmi $(docker images -q email-sender-api) 2>/dev/null || true

echo ""
echo "5️⃣  Пересборка с нуля БЕЗ КЭША"
echo "─────────────────────────────────────────────────────────────"
docker compose build --no-cache --pull api

echo ""
echo "6️⃣  Запуск нового контейнера"
echo "─────────────────────────────────────────────────────────────"
docker compose up -d api

echo ""
echo "⏳ Жду 20 секунд пока API запустится..."
sleep 20

echo ""
echo "7️⃣  Проверка что файл в контейнере правильный"
echo "─────────────────────────────────────────────────────────────"
docker compose exec -T api cat app/views/dashboard/settings/show.html.erb | grep -A 8 "Tracking Settings" | head -12

if docker compose exec -T api cat app/views/dashboard/settings/show.html.erb | grep -q "Events tracked"; then
  echo "❌ ОШИБКА: В контейнере все еще старый код!"
  exit 1
else
  echo "✅ В контейнере новый код без 'Events tracked'"
fi

echo ""
echo "8️⃣  Проверка статуса"
echo "─────────────────────────────────────────────────────────────"
docker compose ps api

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ ОБНОВЛЕНИЕ ЗАВЕРШЕНО                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🔥 ВАЖНО! Обнови браузер с ПОЛНОЙ очисткой кэша:"
echo ""
echo "   Chrome/Edge: Ctrl + Shift + Delete → Очистить кэш"
echo "   Firefox: Ctrl + Shift + Delete → Очистить кэш"
echo "   Safari: Cmd + Option + E"
echo ""
echo "   ИЛИ открой в режиме инкогнито/приватном:"
echo "   Ctrl + Shift + N (Chrome)"
echo "   Ctrl + Shift + P (Firefox)"
echo ""
echo "Затем зайди на:"
echo "   👉 https://linenarrow.com/dashboard/settings"
echo ""
echo "Карточка Tracking должна быть БЕЗ текста 'Events tracked',"
echo "только цифра 0 и иконка графика."
echo ""
