# Исправления системы обработки bounce

## Критические проблемы, которые были исправлены

### 1. ✅ Исправлен расчет bounce_rate

**Проблема:**
```ruby
# Старый код считал только отправленные письма
total_sent = EmailLog.where(status: %w[sent delivered bounced failed]).count
```

Если в очереди было много писем (queued/processing), bounce_rate завышался.

**Пример:**
- 10 писем отправлено (sent/delivered/bounced/failed)
- 5 из них bounce
- 90 писем в очереди (queued/processing)
- **Старый расчет:** 5/10 = 50% bounce rate ❌
- **Новый расчет:** 5/100 = 5% bounce rate ✅

**Исправление:**
```ruby
# Новый код считает ВСЕ письма в временном окне
total_sent = EmailLog.where(campaign_id: campaign_id)
                     .where('created_at > ?', window.minutes.ago)
                     .count
```

**Файл:** `services/api/app/models/mailing_rule.rb:36-39`

---

### 2. ✅ BounceSchedulerJob теперь запускается автоматически

**Проблема:**
- BounceSchedulerJob существовал, но никогда не запускался
- Очистка старых bounce записей (90+ дней) не выполнялась
- База данных росла бесконечно

**Исправление:**
Создан initializer `config/initializers/bounce_scheduler.rb`:
- Запускается при старте приложения (только в production)
- Проверяет наличие таблицы bounced_emails
- Запускает BounceSchedulerJob через 1 минуту после старта
- Далее job работает в цикле раз в 24 часа

**Логирование:**
```
✓ BounceSchedulerJob initialized - will start in 1 minute
```

---

### 3. ✅ Добавлена очистка таблицы delivery_errors

**Проблема:**
- Таблица delivery_errors росла бесконечно
- CleanupOldBouncesJob очищал только bounced_emails и unsubscribes

**Исправление:**
В CleanupOldBouncesJob добавлена очистка delivery_errors:
```ruby
deleted_errors = DeliveryError.where('created_at < ?', 90.days.ago).delete_all
```

**Файл:** `services/api/app/jobs/cleanup_old_bounces_job.rb:18`

---

## Как работает bounce система ПОСЛЕ исправлений

### Процесс обработки bounce:

1. **Postal отправляет webhook** → `WebhooksController.postal`
2. **Классификация ошибки** → `ErrorClassifier.classify()`
3. **Запись в БД:**
   - Hard bounce → таблица `bounced_emails`
   - Все ошибки → таблица `delivery_errors`
4. **Проверка порогов** → `CheckMailingThresholdsJob` (асинхронно)
5. **Остановка рассылки** → через AMS API (если порог превышен)

### Автоматическая очистка данных:

```
Startup → BounceSchedulerJob (через 1 мин)
             ↓
          CleanupOldBouncesJob (каждые 24 часа)
             ↓
          Удаление записей старше 90 дней:
          - bounced_emails
          - unsubscribes
          - delivery_errors
             ↓
          BounceSchedulerJob (повтор через 24 часа)
```

### Блокировка отправки на bounce email:

Проверка выполняется в 3 точках:
- `BuildEmailJob` (перед сборкой письма)
- `SendToPostalJob` (перед отправкой через Postal)
- `SendSmtpEmailJob` (перед отправкой через SMTP)

```ruby
if BouncedEmail.blocked?(email: recipient, campaign_id: campaign_id)
  email_log.update!(status: 'failed', status_details: { reason: 'bounced' })
  return
end
```

### Пороговые значения (по умолчанию):

```
max_bounce_rate: 10%              # Остановить при bounce > 10%
max_rate_limit_errors: 5          # Остановить при 5+ rate limit ошибках
max_spam_blocks: 3                # Остановить при 3+ spam blocks
check_window_minutes: 60          # Проверять последние 60 минут
auto_stop_mailing: true           # Автоостановка включена
```

---

## Команды для применения на сервере

```bash
cd /opt/email-sender
git pull origin claude/fix-api-keys-error-xZ13I
docker compose build api
docker compose up -d api
```

После перезапуска в логах должна появиться строка:
```
✓ BounceSchedulerJob initialized - will start in 1 minute
```

Проверить запуск можно через Sidekiq Web UI или логи:
```bash
docker compose logs api | grep BounceSchedulerJob
```

---

## Что НЕ было исправлено (не критично):

### MonitorBounceCategoriesJob
- Job существует, но нигде не вызывается
- Предназначен для мониторинга bounce категорий
- Не критично для работы системы

### Race condition при блокировке
- Теоретически возможна ситуация: bounce приходит ПОСЛЕ старта BuildEmailJob
- Вероятность мала при нормальной нагрузке
- Можно улучшить добавлением database lock

### Нет UI для управления bounce list
- Нельзя вручную разблокировать email
- Нет экспорта/импорта bounce list
- Nice-to-have функция

---

## Тестирование bounce системы

### 1. Проверка инициализации:
```bash
docker compose logs api | grep "BounceSchedulerJob initialized"
```

Должно быть:
```
✓ BounceSchedulerJob initialized - will start in 1 minute
```

### 2. Проверка очистки (через 24 часа):
```bash
docker compose logs api | grep "CleanupOldBouncesJob"
```

Должно быть:
```
CleanupOldBouncesJob: Deleted X bounce records, Y unsubscribe records, and Z delivery errors older than 90 days
```

### 3. Проверка расчета bounce_rate:
В Rails console:
```ruby
rule = MailingRule.instance
violations = rule.thresholds_exceeded?('campaign_id')
# Должен вернуть false или массив violations
```

### 4. Проверка блокировки bounce email:
```ruby
BouncedEmail.blocked?(email: 'test@example.com', campaign_id: 'campaign_id')
# Должен вернуть true, если email в bounce list
```

---

## Файлы, которые были изменены

1. **services/api/app/models/mailing_rule.rb** - исправлен расчет bounce_rate
2. **services/api/app/jobs/cleanup_old_bounces_job.rb** - добавлена очистка delivery_errors
3. **services/api/config/initializers/bounce_scheduler.rb** (новый) - автозапуск BounceSchedulerJob

---

## Дополнительная информация

### Категории bounce:
- `user_not_found` - пользователь не найден (hard bounce)
- `spam_block` - заблокирован как спам (hard bounce)
- `mailbox_full` - почтовый ящик переполнен (soft bounce)
- `authentication` - ошибка аутентификации
- `rate_limit` - превышен лимит скорости (не bounce)
- `temporary` - временная ошибка (не bounce)
- `connection` - ошибка подключения (не bounce)
- `unknown` - неизвестная ошибка

### Hard bounce vs Soft bounce:
- **Hard bounce** - постоянная ошибка (email навсегда блокируется)
- **Soft bounce** - временная ошибка (может быть повторена)

### Retention policy:
- Bounce записи хранятся 90 дней
- После 90 дней автоматически удаляются
- Можно изменить в `CleanupOldBouncesJob::BOUNCE_RETENTION_DAYS`
