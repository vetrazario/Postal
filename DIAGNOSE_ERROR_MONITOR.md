# Диагностика Error Monitor

Error Monitor пустой. Сейчас проверим почему.

## Быстрая диагностика

### Вариант 1: Rails Runner (САМЫЙ ПРОСТОЙ)

```bash
cd /home/user/Postal
git pull origin claude/project-analysis-errors-Awt4F
docker compose exec api bundle exec rails runner /app/check_error_monitor.rb
```

### Вариант 2: Rake Task

```bash
docker compose exec api bundle exec rake error_monitor:deep_check
```

### Вариант 3: Bash скрипт

```bash
./deep-check-error-monitor.sh
```

---

## Что проверит скрипт

1. ✅ **Таблица delivery_errors** - существует ли, какие колонки
2. ✅ **Количество DeliveryError** - всего в базе и по периодам (1ч, 6ч, 24ч, 48ч, 7д)
3. ✅ **Failed EmailLog** - есть ли failed записи с campaign_id
4. ✅ **Связь EmailLog ↔ DeliveryError** - создаются ли DeliveryError для failed EmailLog
5. ✅ **Симуляция контроллера** - что вернет ErrorMonitorController#index
6. ✅ **Создание теста** - создаст тестовую DeliveryError запись

---

## Возможные результаты

### Результат A: "Всего записей: 0"

**Проблема**: В базе НЕТ DeliveryError записей вообще.

**Причины**:
1. Не было ошибок доставки (маловероятно)
2. DeliveryError не создается при ошибках (BUG)

**Следующий шаг**:
```bash
# Проверить, есть ли failed EmailLog
docker compose exec api bundle exec rails runner "
  failed = EmailLog.where(status: 'failed').count
  puts \"Failed EmailLog: \#{failed}\"

  with_campaign = EmailLog.where(status: 'failed').where.not(campaign_id: nil).count
  puts \"Failed с campaign_id: \#{with_campaign}\"
"
```

Если есть failed EmailLog с campaign_id, но нет DeliveryError - код не создает записи!

---

### Результат B: "Всего записей: N" (N > 0), но "24 часа: 0"

**Проблема**: DeliveryError записи ЕСТЬ, но они старые (>24 часов).

**Причина**: Error Monitor по умолчанию показывает только за последние 24 часа.

**Решение**: В Error Monitor UI измени фильтр на "48 hours" или "7 days".

---

### Результат C: "24 часа: N" (N > 0), но Error Monitor пустой

**Проблема**: Записи есть и свежие, но UI не показывает.

**Причины**:
1. Кеш браузера (Hard Refresh: Ctrl+Shift+R)
2. Ошибка в контроллере/view
3. Записи с другим campaign_id (фильтр активен)

**Решение**:
1. Открой https://linenarrow.com/dashboard/error_monitor
2. Hard Refresh (Ctrl+Shift+R)
3. Сбрось все фильтры (All Campaigns, All Categories, 24 hours)
4. Если не помогло - проверь логи API:
   ```bash
   docker compose logs -f api | grep ErrorMonitor
   ```

---

### Результат D: Тестовая запись создана, но не видна в UI

**Проблема**: Данные в базе, но UI не отображает.

**Причины**:
1. Кеш браузера
2. Ошибка в Rails view/контроллере
3. JavaScript ошибка на странице

**Решение**:
```bash
# Перезапустить API
docker compose restart api

# Проверить логи при открытии страницы
docker compose logs -f api
```

Открой https://linenarrow.com/dashboard/error_monitor и смотри логи.

---

## Если тестовая запись появилась

**✅ Это значит:**
- Контроллер работает
- View работает
- Маршруты работают

**❌ Проблема в том, что:**
- DeliveryError НЕ создается автоматически при ошибках
- Нужно проверить SendSmtpEmailJob и webhooks_controller

**Проверка**:
```bash
# Отправить тестовый email, который точно упадет
docker compose exec api bundle exec rails runner "
  # Создать тестовый EmailLog
  log = EmailLog.create!(
    message_id: 'test-' + SecureRandom.hex(8),
    recipient: 'test@example.com',
    sender: 'noreply@linenarrow.com',
    status: 'queued',
    campaign_id: 'test-campaign'
  )

  # Поставить в очередь отправку с неправильным SMTP
  SendSmtpEmailJob.perform_later({
    email_log_id: log.id,
    envelope: { from: 'wrong@wrong.com', to: 'test@example.com' },
    message: { subject: 'Test', text: 'Test' }
  })

  puts 'Job queued, wait 10 seconds...'
"

# Подождать 10 секунд
sleep 10

# Проверить DeliveryError
docker compose exec api bundle exec rails runner "
  puts 'DeliveryError count: ' + DeliveryError.count.to_s
  last = DeliveryError.order(created_at: :desc).first
  if last
    puts 'Last DeliveryError: campaign=' + last.campaign_id.to_s
  end
"
```

---

## Если ничего не помогло

Пришли вывод скрипта:
```bash
docker compose exec api bundle exec rails runner /app/check_error_monitor.rb > /tmp/error_monitor_diagnostic.txt 2>&1
cat /tmp/error_monitor_diagnostic.txt
```

Скопируй весь вывод и покажи мне.

---

## Краткая проверка (без скриптов)

Если хочешь быстро проверить вручную:

```bash
# 1. Есть ли DeliveryError?
docker compose exec api bundle exec rails runner "puts DeliveryError.count"

# 2. Есть ли свежие (24ч)?
docker compose exec api bundle exec rails runner "puts DeliveryError.where('created_at > ?', 24.hours.ago).count"

# 3. Создать тестовую
docker compose exec api bundle exec rake error_monitor:create_test

# 4. Проверить в UI
# Открыть: https://linenarrow.com/dashboard/error_monitor
```

---

## Ожидаемый вывод (если все OK)

```
===================================================================
ГЛУБОКАЯ ПРОВЕРКА ERROR MONITOR
===================================================================

=== 1. Проверка таблицы delivery_errors ===
✅ Таблица delivery_errors существует

Колонки:
  - id (integer)
  - email_log_id (integer)
  - campaign_id (string)
  - category (string)
  - smtp_code (integer)
  - smtp_message (text)
  - recipient_domain (string)
  - created_at (datetime)
  - updated_at (datetime)

=== 2. Общее количество DeliveryError ===
Всего записей: 125
Самая старая: 2026-01-15 10:23:45 UTC
Самая новая: 2026-01-18 14:32:11 UTC

Последние 10 записей:
  #125: campaign=campaign-123, category=rate_limit, recipient=t***@example.com, created=2026-01-18 14:32:11
  ...

=== 3. DeliveryError за разные периоды ===
1 час     : 5 записей
6 часов   : 23 записей
24 часа   : 87 записей
48 часов  : 115 записей
7 дней    : 125 записей

=== 4. Failed EmailLog (последние 7 дней) ===
Всего failed: 130
  С campaign_id: 125
  БЕЗ campaign_id: 5

Проверка: есть ли DeliveryError для failed EmailLog?
  Failed EmailLog с campaign_id: 125
  DeliveryError для них: 125
  РАЗНИЦА (должно быть 0): 0

=== 5. Симуляция контроллера ErrorMonitorController ===
Запрос за последние 24 часов: 87 записей

Статистика по категориям:
  rate_limit: 45
  spam_block: 23
  user_not_found: 12
  temporary: 7

Кампании: campaign-123, campaign-456, campaign-789

=== 6. Создание тестовой записи DeliveryError ===
EmailLog найден: #12345, campaign=campaign-123
✅ ТЕСТОВАЯ ЗАПИСЬ СОЗДАНА!
  ID: 126
  Campaign: campaign-123
  Created: 2026-01-18 15:00:00 UTC

🔍 ПРОВЕРЬТЕ ERROR MONITOR:
   https://linenarrow.com/dashboard/error_monitor

   Эта запись ДОЛЖНА появиться в списке!
   Если НЕ появилась - проблема в контроллере/view/маршрутах

===================================================================
ПРОВЕРКА ЗАВЕРШЕНА
===================================================================
```

---

## Действия после диагностики

1. **Запусти скрипт**:
   ```bash
   docker compose exec api bundle exec rails runner /app/check_error_monitor.rb
   ```

2. **Скопируй весь вывод** и покажи мне

3. **Проверь Error Monitor** после создания тестовой записи:
   https://linenarrow.com/dashboard/error_monitor

4. **Скажи что видишь** - появилась тестовая запись или нет

---

Коммит: `bafaaa9`
Ветка: `claude/project-analysis-errors-Awt4F`
