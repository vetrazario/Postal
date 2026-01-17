# Error Monitor Fix - DeliveryError не создается

## Проблема

Ошибки не попадают в Error Monitor, несмотря на наличие failed EmailLog записей.

## Причина

**DeliveryError требует обязательный `campaign_id`**, но код не проверял его наличие перед созданием:

1. **В модели DeliveryError** (app/models/delivery_error.rb:18):
   ```ruby
   validates :campaign_id, presence: true
   ```

2. **В SendSmtpEmailJob** - создание DeliveryError без проверки campaign_id:
   ```ruby
   DeliveryError.create!(
     campaign_id: email_log.campaign_id,  # Может быть nil!
     ...
   )
   ```
   Если `campaign_id == nil`, валидация падает, но ошибка проглатывается в rescue блоке.

3. **В webhooks_controller** - уже была проверка `if campaign_id.present?`, но без логирования.

## Решение

### 1. SendSmtpEmailJob - добавлена проверка campaign_id

**До:**
```ruby
# Create delivery error record
DeliveryError.create!(
  email_log_id: email_log.id,
  campaign_id: email_log.campaign_id,  # ОПАСНО: может быть nil
  category: categorize_error(response[:error]),
  smtp_message: response[:error].to_s.truncate(1000),
  recipient_domain: email_log.recipient.split('@').last
)
```

**После:**
```ruby
# Create delivery error record (only if campaign_id present)
if email_log.campaign_id.present?
  DeliveryError.create!(
    email_log_id: email_log.id,
    campaign_id: email_log.campaign_id,
    category: categorize_error(response[:error]),
    smtp_message: response[:error].to_s.truncate(1000),
    recipient_domain: email_log.recipient.split('@').last
  )
  Rails.logger.info "[SendSmtpEmailJob] DeliveryError created: campaign=#{email_log.campaign_id}, category=..."
else
  Rails.logger.warn "[SendSmtpEmailJob] DeliveryError NOT created - no campaign_id for EmailLog #{email_log.id}"
end
```

### 2. WebhooksController - добавлено логирование

**MessageBounced/MessageDeliveryFailed** (уже была проверка, добавили логирование):
```ruby
if email_log.campaign_id.present?
  DeliveryError.create!(...)
  Rails.logger.info "[WebhooksController] DeliveryError created for #{event}: campaign=..."
else
  Rails.logger.warn "[WebhooksController] DeliveryError NOT created - no campaign_id..."
end
```

**MessageHeld** (аналогично):
```ruby
if email_log.campaign_id.present?
  DeliveryError.create!(...)
  Rails.logger.info "[WebhooksController] DeliveryError created for MessageHeld: campaign=..."
else
  Rails.logger.warn "[WebhooksController] DeliveryError NOT created - no campaign_id..."
end
```

## Файлы изменены

- `services/api/app/jobs/send_smtp_email_job.rb` (2 места: строки 108 и 136)
- `services/api/app/controllers/api/v1/webhooks_controller.rb` (2 места: строки 99 и 141)

## Диагностические скрипты

### `check-campaign-ids.sh`
Показывает, у каких EmailLog записей отсутствует campaign_id:
```bash
./check-campaign-ids.sh
```

Выведет:
- Количество failed EmailLog с/без campaign_id
- Количество bounced EmailLog с/без campaign_id
- Список EmailLog БЕЗ campaign_id (если есть)
- Логи создания DeliveryError

### `check-delivery-errors.sh`
Показывает DeliveryError записи и статистику:
```bash
./check-delivery-errors.sh
```

## Инструкции по развертыванию

### 1. Подтянуть изменения
```bash
cd /home/user/Postal
git pull origin claude/project-analysis-errors-Awt4F
```

### 2. Перезапустить контейнеры
```bash
docker compose stop api sidekiq
docker compose rm -f api sidekiq
docker compose build --no-cache api
docker compose up -d
```

### 3. Проверить текущее состояние
```bash
./check-campaign-ids.sh
```

**Если увидите "WITHOUT campaign_id: > 0"** - это означает, что у EmailLog записей нет campaign_id, и DeliveryError НЕ МОЖЕТ быть создан (валидация запрещает).

## Тестирование

### Тест 1: Отправка email через SMTP
1. Отправьте тестовый email через SMTP relay, который точно зафейлится
2. Проверьте логи Sidekiq:
   ```bash
   docker compose logs -f sidekiq | grep DeliveryError
   ```

**Ожидаемый результат:**
- Если campaign_id есть: `[SendSmtpEmailJob] DeliveryError created: campaign=XXX`
- Если campaign_id нет: `[SendSmtpEmailJob] DeliveryError NOT created - no campaign_id for EmailLog XXX`

### Тест 2: Webhook от Postal
1. Отправьте тестовую кампанию
2. Проверьте логи API:
   ```bash
   docker compose logs -f api | grep DeliveryError
   ```

**Ожидаемый результат:**
- Для bounce/held: `[WebhooksController] DeliveryError created for MessageBounced: campaign=XXX`
- Или: `[WebhooksController] DeliveryError NOT created - no campaign_id...`

### Тест 3: Error Monitor UI
1. Перейдите на https://linenarrow.com/dashboard/error_monitor
2. Проверьте, появляются ли ошибки

**Если ошибки НЕ появляются:**
- Запустите `./check-campaign-ids.sh`
- Если "WITHOUT campaign_id" > 0 - значит EmailLog создаются без campaign_id
- Нужно исследовать, ПОЧЕМУ campaign_id не передается при создании EmailLog

## Возможные причины отсутствия campaign_id

1. **SMTP relay без campaign_id**:
   - Emails отправляются напрямую через SMTP, а не через campaign
   - В этом случае campaign_id действительно будет nil
   - **Решение**: Error Monitor не будет показывать такие ошибки (это нормально для SMTP relay)

2. **Bug в коде создания EmailLog**:
   - Campaign существует, но campaign_id не передается в EmailLog
   - Нужно проверить, где создается EmailLog

3. **Webhook без campaign_id**:
   - Postal отправляет webhook, но не передает campaign_id
   - Нужно проверить payload webhooks

## Следующие шаги

1. **Развернуть изменения** (см. выше)
2. **Запустить диагностику**: `./check-campaign-ids.sh`
3. **Если campaign_id отсутствует** у всех failed EmailLog:
   - Проверить, как создается EmailLog (найти место создания)
   - Убедиться, что campaign_id передается при создании
4. **Если campaign_id присутствует**:
   - DeliveryError будет создаваться
   - Ошибки появятся в Error Monitor

## Коммит

**Коммит:** `2e0b8a2`
**Ветка:** `claude/project-analysis-errors-Awt4F`

---

## Краткая суть

**Проблема:** DeliveryError требует campaign_id, но код не проверял его наличие

**Решение:** Добавлена проверка `if campaign_id.present?` перед созданием DeliveryError

**Результат:**
- Если campaign_id есть → DeliveryError создается → ошибка в Error Monitor ✅
- Если campaign_id нет → WARNING в логах → нужно разобраться, почему нет campaign_id
