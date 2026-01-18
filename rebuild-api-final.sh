#!/bin/bash
set -e

cd /opt/email-sender

echo "==================================================================="
echo "ПЕРЕСБОРКА API С ИСПРАВЛЕНИЯМИ ERROR MONITOR"
echo "==================================================================="
echo ""

echo "Изменения которые будут применены:"
echo "1. ✅ DeliveryError.create! с проверкой campaign_id в SendSmtpEmailJob"
echo "2. ✅ DeliveryError.create! в webhooks_controller для MessageHeld"
echo "3. ✅ DeliveryError.create! в webhooks_controller для MessageBounced"
echo "4. ✅ Логирование успеха/неудачи создания DeliveryError"
echo ""

read -p "Продолжить пересборку? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Отменено"
    exit 1
fi

echo ""
echo "=== 1. Остановка API и Sidekiq ==="
docker compose stop api sidekiq

echo ""
echo "=== 2. Удаление контейнеров ==="
docker compose rm -f api sidekiq

echo ""
echo "=== 3. Пересборка с --no-cache ==="
docker compose build --no-cache api

echo ""
echo "=== 4. Запуск всех сервисов ==="
docker compose up -d

echo ""
echo "=== 5. Ожидание запуска (30 секунд) ==="
sleep 30

echo ""
echo "=== 6. Проверка что код обновился ==="
echo "Проверяем наличие нового кода в контейнере..."
docker compose exec -T api bash -c "grep -c 'DeliveryError created for MessageHeld' app/controllers/api/v1/webhooks_controller.rb" && echo "✅ Новый код найден!" || echo "❌ Код не найден!"

echo ""
echo "=== 7. Проверка логов ==="
echo "Проверка что Sidekiq запустился..."
docker compose logs --tail=20 sidekiq | grep -i "Sidekiq.*starting" || echo "Проверьте логи вручную"

echo ""
echo "==================================================================="
echo "✅ ПЕРЕСБОРКА ЗАВЕРШЕНА"
echo "==================================================================="
echo ""
echo "Теперь:"
echo "1. Отправьте тестовое письмо которое точно упадет"
echo "2. Проверьте логи: docker compose logs -f api sidekiq | grep DeliveryError"
echo "3. Проверьте Error Monitor: https://linenarrow.com/dashboard/error_monitor"
echo ""
