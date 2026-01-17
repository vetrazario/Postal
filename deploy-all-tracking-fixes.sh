#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ПРИМЕНЕНИЕ ВСЕХ ИСПРАВЛЕНИЙ ТРЕКИНГА                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /opt/email-sender

echo "1️⃣  Подтягиваю последние изменения"
echo "─────────────────────────────────────────────────────────────"
git pull origin claude/project-analysis-errors-Awt4F

echo ""
echo "2️⃣  Пересобираю API (webhook handler обновлен)"
echo "─────────────────────────────────────────────────────────────"
docker compose build api

echo ""
echo "3️⃣  Перезапускаю API"
echo "─────────────────────────────────────────────────────────────"
docker compose restart api

echo ""
echo "⏳ Жду 15 секунд..."
sleep 15

echo ""
echo "4️⃣  Проверяю статус API"
echo "─────────────────────────────────────────────────────────────"
docker compose ps api

echo ""
echo "5️⃣  Проверяю последние логи API"
echo "─────────────────────────────────────────────────────────────"
docker compose logs api --tail=20

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ ДЕПЛОЙ ЗАВЕРШЕН                                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Что было исправлено:"
echo "  1. ✅ MessageHeld webhook теперь создает DeliveryError"
echo "  2. ✅ Ошибки из suppression list попадут в error monitor"
echo "  3. ✅ Rate limit ошибки логируются"
echo ""
echo "Теперь запусти диагностику:"
echo "  ./diagnose-tracking.sh"
echo ""
echo "И тест tracking URL:"
echo "  ./test-tracking-url.sh"
echo ""
echo "После этого отправь тестовое письмо и проверь:"
echo "  1. Зайди на https://linenarrow.com/dashboard/error_monitor"
echo "  2. Кликни по ссылке в письме"
echo "  3. Проверь что redirectит на YouTube"
echo ""
