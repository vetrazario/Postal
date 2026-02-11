# Troubleshooting Guide

## Быстрая диагностика

### Команды для проверки состояния

```bash
# Статус всех сервисов
docker compose ps

# Логи всех сервисов
docker compose logs -f --tail=100

# Логи конкретного сервиса
docker compose logs -f api
docker compose logs -f sidekiq
docker compose logs -f postal

# Health check API
curl -s https://DOMAIN/api/v1/health | jq

# Проверка очередей Sidekiq
docker compose exec api rails runner "puts Sidekiq::Stats.new.to_json"

# Проверка PostgreSQL
docker compose exec postgres psql -U email_sender -c "SELECT 1"

# Проверка Redis
docker compose exec redis redis-cli ping
```

---

## Проблемы и решения

### 1. API возвращает 401 Unauthorized

**Симптомы:**
```json
{"error":{"code":"invalid_api_key","message":"API key is invalid or expired"}}
```

**Причины:**
1. Неверный API ключ
2. Ключ деактивирован
3. Ключ не создан

**Решение:**

```bash
# Проверить существующие ключи
docker compose exec api rails runner "ApiKey.all.each { |k| puts \"#{k.id}: #{k.name} (active: #{k.active})\" }"

# Создать новый ключ
docker compose exec api rails runner "
  key = ApiKey.create!(name: 'AMS Production')
  puts 'API Key: ' + key.raw_key
  puts 'Save this key! It will not be shown again.'
"
```

---

### 2. API возвращает 422 Validation Error

**Симптомы:**
```json
{"error":{"code":"validation_error","details":[{"field":"from_email","message":"domain is not authorized"}]}}
```

**Причины:**
1. Домен отправителя не в списке разрешённых
2. Неверный формат email
3. Отсутствует обязательное поле

**Решение:**

```bash
# Проверить разрешённые домены
cat .env | grep ALLOWED_SENDER_DOMAINS

# Добавить домен (редактировать .env)
nano .env
# ALLOWED_SENDER_DOMAINS=example.com,newdomain.com

# Перезапустить API
docker compose restart api sidekiq
```

---

### 3. Письма не отправляются (stuck in queue)

**Симптомы:**
- Статус писем остаётся "queued" или "processing"
- Очередь Sidekiq растёт

**Диагностика:**

```bash
# Проверить очереди
docker compose exec api rails runner "
  stats = Sidekiq::Stats.new
  puts 'Enqueued: ' + stats.enqueued.to_s
  puts 'Processing: ' + stats.processes_size.to_s
  puts 'Failed: ' + stats.failed.to_s
"

# Проверить логи Sidekiq
docker compose logs sidekiq --tail=50

# Проверить подключение к Postal
docker compose exec api rails runner "
  require 'net/http'
  uri = URI(ENV['POSTAL_API_URL'] + '/api/v1/messages')
  http = Net::HTTP.new(uri.host, uri.port)
  puts http.get(uri.path).code
"
```

**Решения:**

```bash
# Перезапустить Sidekiq
docker compose restart sidekiq

# Если Postal недоступен
docker compose restart postal

# Проверить подключение Postal к RabbitMQ
docker compose logs postal | grep -i "rabbit\|error"
```

---

### 4. Postal не отправляет (SMTP ошибки)

**Симптомы:**
- Письма застревают в очереди Postal
- Ошибки в логах Postal

**Диагностика:**

```bash
# Логи Postal
docker compose logs postal --tail=100

# Проверить SMTP подключение
docker compose exec postal postal test-smtp user@gmail.com

# Проверить DNS
docker compose exec postal dig MX gmail.com
docker compose exec postal dig TXT _dmarc.YOUR_DOMAIN
```

**Частые проблемы:**

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `Connection refused` | Порт 25 заблокирован | Проверить firewall провайдера |
| `No route to host` | Сетевые проблемы | Проверить DNS, сеть |
| `550 5.7.1 SPF fail` | SPF не настроен | Добавить SPF запись |
| `550 5.7.1 DKIM fail` | DKIM не настроен | Добавить DKIM запись |
| `421 Too many connections` | Rate limiting | Уменьшить скорость отправки |

---

### 5. Высокий bounce rate

**Симптомы:**
- Много писем со статусом "bounced"
- Bounce rate > 2%

**Диагностика:**

```bash
# Статистика bounce
docker compose exec api rails runner "
  total = EmailLog.where('created_at > ?', 1.day.ago).count
  bounced = EmailLog.where('created_at > ?', 1.day.ago).where(status: 'bounced').count
  puts 'Bounce rate: ' + (bounced.to_f / total * 100).round(2).to_s + '%'
"

# Причины bounce
docker compose exec api rails runner "
  EmailLog.where(status: 'bounced').last(10).each do |log|
    puts log.status_details
  end
"
```

**Решения:**

1. **Hard bounce** — удалить email из списка
2. **Soft bounce** — повторить позже
3. **Spam complaint** — удалить и добавить в blacklist

---

### 6. База данных переполнена

**Симптомы:**
- Ошибки "disk full"
- Медленные запросы

**Диагностика:**

```bash
# Размер таблиц
docker compose exec postgres psql -U email_sender -c "
  SELECT 
    relname as table,
    pg_size_pretty(pg_total_relation_size(relid)) as size
  FROM pg_catalog.pg_statio_user_tables
  ORDER BY pg_total_relation_size(relid) DESC;
"

# Количество записей
docker compose exec api rails runner "
  puts 'email_logs: ' + EmailLog.count.to_s
  puts 'tracking_events: ' + TrackingEvent.count.to_s
"
```

**Решение — очистка старых данных:**

```bash
# Удалить логи старше 30 дней
docker compose exec api rails runner "
  EmailLog.where('created_at < ?', 30.days.ago).delete_all
"

# Удалить события старше 90 дней
docker compose exec api rails runner "
  TrackingEvent.where('created_at < ?', 90.days.ago).delete_all
"

# Vacuum (освободить место)
docker compose exec postgres psql -U email_sender -c "VACUUM FULL;"
```

---

### 7. Redis out of memory

**Симптомы:**
- Ошибки "OOM command not allowed"
- Sidekiq не работает

**Диагностика:**

```bash
# Использование памяти Redis
docker compose exec redis redis-cli info memory

# Количество ключей
docker compose exec redis redis-cli dbsize
```

**Решение:**

```bash
# Очистить устаревшие ключи
docker compose exec redis redis-cli FLUSHDB

# Увеличить лимит памяти
# В docker-compose.yml добавить:
# redis:
#   command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
```

---

### 8. Redis: Bad file format (AOF) / Memory overcommit

**Симптомы в логах Redis:**
- `Bad file format reading the append only file appendonly.aof.6.incr.aof`
- `WARNING Memory overcommit must be enabled!`

**Решение 1 — починить AOF (скрипт):**

```bash
cd /opt/email-sender
chmod +x scripts/fix-redis-aof.sh
./scripts/fix-redis-aof.sh
```

Если починка не удалась, скрипт предложит удалить том и поднять Redis с пустой БД (очереди Sidekiq очистятся).

**Решение 2 — вручную сбросить Redis:**

```bash
docker compose stop redis
docker volume rm email_redis_data
docker compose up -d redis
```

**Устранить предупреждение Memory overcommit (на хосте):**

```bash
sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf
```

После изменения `sysctl` перезагрузка не обязательна; для постоянного применения при перезагрузке достаточно добавления в `/etc/sysctl.conf`.

---

### 9. SSL сертификат истёк

**Симптомы:**
- Браузер показывает "Not Secure"
- API возвращает SSL ошибки

**Решение:**

```bash
# Обновить сертификат
docker compose run --rm certbot certbot renew

# Перезапустить nginx
docker compose restart nginx

# Проверить сертификат
echo | openssl s_client -connect DOMAIN:443 2>/dev/null | openssl x509 -noout -dates
```

**Автоматическое обновление:**

```bash
# Добавить в crontab
0 0 * * * cd /opt/email-sender && docker compose run --rm certbot certbot renew && docker compose restart nginx
```

---

### 10. Tracking не работает

**Симптомы:**
- Нет данных об открытиях
- Клики не регистрируются

**Диагностика:**

```bash
# Проверить tracking сервис
curl -I https://DOMAIN/track/o?eid=test&cid=test&mid=test

# Логи tracking
docker compose logs tracking --tail=50

# Проверить события в БД
docker compose exec api rails runner "
  puts TrackingEvent.last(5).map(&:to_json)
"
```

**Частые проблемы:**

1. **Nginx не проксирует /track/** — проверить конфиг nginx
2. **Tracking сервис не запущен** — `docker compose restart tracking`
3. **Redis недоступен** — `docker compose restart redis`

---

### 11. Webhook'и не доходят до AMS

**Симптомы:**
- AMS не получает статусы
- Нет данных о доставке/открытиях

**Диагностика:**

```bash
# Проверить подключение к AMS
docker compose exec api curl -I $AMS_CALLBACK_URL

# Логи отправки webhook
docker compose logs sidekiq | grep -i webhook

# Проверить failed jobs
docker compose exec api rails runner "
  Sidekiq::RetrySet.new.each { |job| puts job.klass + ': ' + job.error_message }
"
```

**Решение:**

```bash
# Проверить URL в .env
cat .env | grep AMS_CALLBACK

# Повторить неудачные jobs
docker compose exec api rails runner "
  Sidekiq::RetrySet.new.each(&:retry)
"
```

---

## Логи

### Где искать логи

| Сервис | Путь | Что содержит |
|--------|------|--------------|
| API | `docker compose logs api` | HTTP запросы, ошибки Rails |
| Sidekiq | `docker compose logs sidekiq` | Job processing, ошибки |
| Postal | `docker compose logs postal` | SMTP, доставка |
| Nginx | `docker compose logs nginx` | Access/error logs |
| PostgreSQL | `docker compose logs postgres` | SQL запросы, ошибки |

### Полезные grep команды

```bash
# Все ошибки
docker compose logs 2>&1 | grep -i "error\|exception\|failed"

# Конкретный message_id
docker compose logs 2>&1 | grep "msg_12345"

# Конкретный IP
docker compose logs 2>&1 | grep "1.2.3.4"

# Bounce'ы
docker compose logs postal | grep -i bounce
```

---

## Мониторинг

### Prometheus метрики

Если установлен Prometheus, ключевые метрики:

```
# Очередь Sidekiq
sidekiq_queue_size{queue="default"}
sidekiq_queue_size{queue="mailers"}

# Время обработки
sidekiq_job_duration_seconds

# HTTP запросы
http_requests_total{status="200"}
http_requests_total{status="500"}

# Bounce rate
email_bounced_total / email_sent_total
```

### Алерты

```yaml
# alertmanager rules
groups:
  - name: email-sender
    rules:
      - alert: HighBounceRate
        expr: email_bounced_total / email_sent_total > 0.02
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "High bounce rate detected"
      
      - alert: QueueBacklog
        expr: sidekiq_queue_size > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Sidekiq queue backlog"
      
      - alert: ServiceDown
        expr: up{job="email-sender"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
```

---

### 12. Миграции не применяются (bin/rails отсутствует)

**Симптомы:**
- Новые страницы Dashboard выдают 500 ошибку
- При запуске контейнера вместо миграций выводится справка `rails new`
- Таблицы не создаются в БД

**Диагностика:**

```bash
# Проверить наличие bin/rails в контейнере
docker compose exec api ls -la /app/bin

# Проверить таблицы в БД
docker compose exec postgres psql -U email_sender -d email_sender -c "\dt"

# Попробовать запустить миграции
docker compose exec api bundle exec rails db:migrate:status
```

Если вместо результата выводится справка по `rails new` — файл `bin/rails` отсутствует.

**Причина:**
Файлы `bin/rails`, `bin/rake`, `bin/bundle` отсутствуют в репозитории или не скопировались в контейнер.

**Решение:**

1. **Создать недостающие файлы:**

`services/api/bin/rails`:
```ruby
#!/usr/bin/env ruby
APP_PATH = File.expand_path("../config/application", __dir__)
require_relative "../config/boot"
require "rails/commands"
```

`services/api/bin/rake`:
```ruby
#!/usr/bin/env ruby
require_relative "../config/boot"
require "rake"
Rake.application.run
```

`services/api/bin/bundle`:
```ruby
#!/usr/bin/env ruby
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
require "bundler/setup"
load Gem.bin_path("bundler", "bundle")
```

2. **Закоммитить и запушить:**
```bash
git add services/api/bin/
git commit -m "Add bin/rails, bin/rake, bin/bundle"
git push origin <branch>
```

3. **На сервере пересобрать контейнеры:**
```bash
cd /opt/email-sender
git pull origin <branch>
docker compose build --no-cache api sidekiq
docker compose up -d api sidekiq
```

**Временное решение (создать таблицы вручную):**

```bash
# Создать таблицы через SQL напрямую
docker compose exec postgres psql -U email_sender -d email_sender -c "
CREATE TABLE IF NOT EXISTS <table_name> (
  ...
);
"

# Перезапустить сервисы
docker compose restart api sidekiq
```

---

## Контакты для эскалации

При неразрешимых проблемах:

1. Проверить GitHub Issues проекта
2. Создать новый Issue с:
   - Описанием проблемы
   - Логами (без PII!)
   - Шагами воспроизведения
   - Версией системы

