# 🔧 СПИСОК НЕОБХОДИМЫХ ИСПРАВЛЕНИЙ

> **Дата анализа**: 2026-01-02
> **Статус проекта**: 90% готовности
> **Всего найдено проблем**: 23

---

## 📋 БЫСТРАЯ НАВИГАЦИЯ

- [🔴 КРИТИЧНЫЕ ПРОБЛЕМЫ](#-критичные-проблемы-исправить-немедленно) (3 проблемы)
- [🟡 ВАЖНЫЕ ПРОБЛЕМЫ](#-важные-проблемы-исправить-на-этой-неделе) (6 проблем)
- [🟢 СРЕДНИЙ ПРИОРИТЕТ](#-средний-приоритет-исправить-в-течение-месяца) (7 проблем)
- [🔵 НИЗКИЙ ПРИОРИТЕТ](#-низкий-приоритет-улучшения) (7 проблем)

---

## 🔴 КРИТИЧНЫЕ ПРОБЛЕМЫ (исправить НЕМЕДЛЕННО)

### 1. ❌ Не работает проверка подписи Postal webhook

**Приоритет**: 🔴 КРИТИЧНО
**Категория**: Безопасность
**Риск**: Атакующий может отправлять поддельные webhooks с ложными статусами доставки

**Где находится**:
```
services/api/app/controllers/api/v1/webhooks_controller.rb:80
```

**Проблема**:
```ruby
# TODO: Fix Postal webhook signature verification
def verify_postal_signature
  # Временно пропускаем проверку
  return true
end
```

**Как исправить**:
```ruby
# services/api/app/controllers/api/v1/webhooks_controller.rb

def verify_postal_signature
  signature = request.headers['X-Postal-Signature']
  return false if signature.blank?

  public_key_path = ENV['POSTAL_WEBHOOK_PUBLIC_KEY_FILE']
  public_key = OpenSSL::PKey::RSA.new(File.read(public_key_path))

  payload = request.body.read
  digest = OpenSSL::Digest::SHA256.new

  public_key.verify(digest, Base64.decode64(signature), payload)
rescue => e
  Rails.logger.error("Postal signature verification failed: #{e.message}")
  false
end
```

**Тесты**:
```ruby
# spec/requests/api/v1/webhooks_spec.rb
RSpec.describe 'POST /api/v1/webhook', type: :request do
  context 'with invalid signature' do
    it 'returns 401' do
      post '/api/v1/webhook', params: {}, headers: { 'X-Postal-Signature': 'invalid' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

**Время на исправление**: 2-3 часа
**Зависимости**: Нужен публичный ключ Postal (файл postal_public.key уже в проекте)

---

### 2. ❌ Отсутствует .env файл

**Приоритет**: 🔴 КРИТИЧНО
**Категория**: Конфигурация
**Риск**: При деплое могут использоваться дефолтные пароли типа "CHANGE_ME"

**Где находится**:
```
/home/user/Postal/.env (файл отсутствует)
env.example.txt (есть только пример)
```

**Проблема**:
- Файл `.env` не создан
- В примере много "CHANGE_ME" значений
- Нет автоматической генерации секретов

**Как исправить**:

```bash
# Запустить скрипт генерации
./scripts/setup-local.sh

# ИЛИ вручную создать .env
cp env.example.txt .env

# Сгенерировать все секреты
cat > .env << EOF
DOMAIN=linenarrow.com
LETSENCRYPT_EMAIL=admin@linenarrow.com
RAILS_ENV=production

# Database passwords
POSTGRES_PASSWORD=$(openssl rand -hex 16)
MARIADB_PASSWORD=$(openssl rand -hex 16)
RABBITMQ_PASSWORD=$(openssl rand -hex 16)

# Application secrets
SECRET_KEY_BASE=$(openssl rand -hex 32)
POSTAL_SIGNING_KEY=$(openssl rand -hex 32)
WEBHOOK_SECRET=$(openssl rand -hex 32)
API_KEY=$(openssl rand -hex 24)

# Encryption keys
ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)
ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)
ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)

# Dashboard credentials
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=$(openssl rand -base64 16)

# AMS Integration
AMS_CALLBACK_URL=https://ams.example.com/api/webhooks/send_server
ALLOWED_SENDER_DOMAINS=linenarrow.com
DAILY_LIMIT=50000
EOF
```

**Автоматизация**:
```bash
# Добавить в install.sh проверку
if [ ! -f .env ]; then
  echo "Creating .env file..."
  # автогенерация
fi
```

**Время на исправление**: 1 час
**Зависимости**: Нет

---

### 3. ❌ Не проведено end-to-end тестирование

**Приоритет**: 🔴 КРИТИЧНО
**Категория**: Тестирование
**Риск**: Неизвестно, работает ли полный flow от AMS до получателя

**Где находится**:
```
CURRENT_STATUS.md:6 - Phase 6: Testing & Deployment ⏳ 0%
```

**Проблема**:
- Система собрана, но не протестирована полностью
- Нет уверенности, что все компоненты работают вместе

**Как исправить**:

**Шаг 1: Подготовка**
```bash
# 1. Запустить систему
docker compose up -d

# 2. Дождаться готовности всех сервисов
docker compose ps

# 3. Выполнить миграции
docker compose exec api rails db:create db:migrate

# 4. Инициализировать Postal
docker compose exec postal postal initialize
docker compose exec postal postal make-user
```

**Шаг 2: Тестирование HTTP API**
```bash
# Создать API ключ
API_KEY=$(docker compose exec -T api rails runner "
  api_key, raw_key = ApiKey.generate(name: 'Test Key')
  puts raw_key
")

# Отправить тестовое письмо
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "from_email": "sender@linenarrow.com",
    "from_name": "Test Sender",
    "subject": "Test Email",
    "html_body": "<html><body><h1>Test</h1><a href=\"https://example.com\">Click</a></body></html>",
    "tracking": {
      "campaign_id": "test_campaign",
      "message_id": "test_msg_001"
    }
  }'

# Проверить статус
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost/api/v1/status/test_msg_001
```

**Шаг 3: Тестирование SMTP Relay**
```bash
# Создать SMTP credentials в Dashboard
# URL: http://localhost/dashboard/smtp_credentials

# Отправить через SMTP (используя telnet или swaks)
swaks --to test@example.com \
      --from sender@linenarrow.com \
      --server localhost:2587 \
      --auth-user smtp_user \
      --auth-password smtp_password \
      --tls \
      --body "Test email via SMTP"
```

**Шаг 4: Тестирование tracking**
```bash
# Open tracking
curl "http://localhost/track/o?eid=$(echo -n 'test@example.com' | base64)&cid=$(echo -n 'test_campaign' | base64)&mid=$(echo -n 'test_msg_001' | base64)"

# Click tracking
curl -L "http://localhost/track/c?url=$(echo -n 'https://example.com' | base64)&eid=$(echo -n 'test@example.com' | base64)&cid=$(echo -n 'test_campaign' | base64)&mid=$(echo -n 'test_msg_001' | base64)"
```

**Шаг 5: Проверка логов**
```bash
# Проверить логи API
docker compose logs api | grep "test_msg_001"

# Проверить Sidekiq
docker compose logs sidekiq | grep "test_msg_001"

# Проверить Postal
docker compose logs postal | grep "test@example.com"
```

**Критерии успеха**:
- ✅ API возвращает message_id
- ✅ Email появляется в базе с status='queued'
- ✅ Sidekiq обрабатывает BuildEmailJob
- ✅ Postal отправляет письмо
- ✅ Tracking открытия работает
- ✅ Tracking кликов работает
- ✅ Webhook отправляется в AMS

**Время на исправление**: 4-6 часов
**Зависимости**: Нужен доступ к SMTP серверу для получения реального письма

---

## 🟡 ВАЖНЫЕ ПРОБЛЕМЫ (исправить на этой неделе)

### 4. ⚠️ SMTP Relay не применяет rate limiting

**Приоритет**: 🟡 ВАЖНО
**Категория**: Безопасность
**Риск**: Brute force атака на SMTP credentials

**Где находится**:
```
services/smtp-relay/plugins/smtp_auth.js
services/api/app/models/smtp_credential.rb:5-6 (rate_limit определен, но не используется)
```

**Проблема**:
```javascript
// smtp_auth.js - проверяет только password
const isValid = await bcrypt.compare(password, credential.password_hash);
// НО: не проверяет rate_limit из БД!
```

**Как исправить**:

```javascript
// services/smtp-relay/plugins/smtp_auth.js

const Redis = require('redis');
const redisClient = Redis.createClient({ url: process.env.REDIS_URL });

async function checkRateLimit(username, ipAddress) {
  const key = `smtp_auth_attempts:${username}:${ipAddress}`;
  const attempts = await redisClient.incr(key);

  if (attempts === 1) {
    await redisClient.expire(key, 3600); // 1 hour
  }

  // Get rate_limit from credential
  const credential = await getCredential(username);
  if (attempts > credential.rate_limit) {
    throw new Error('Rate limit exceeded');
  }
}

// В hook_connect добавить:
await checkRateLimit(username, connection.remote.ip);
```

**Время на исправление**: 3-4 часа
**Зависимости**: Redis (уже есть в проекте)

---

### 5. ⚠️ Нет backup стратегии для баз данных

**Приоритет**: 🟡 ВАЖНО
**Категория**: Надежность
**Риск**: Потеря всех данных при отказе диска

**Где находится**:
```
docker-compose.yml - volumes созданы, но нет backup
```

**Проблема**:
- PostgreSQL данные в volume `postgres_data`
- MariaDB данные в volume `mariadb_data`
- Нет автоматического резервного копирования
- Нет плана восстановления

**Как исправить**:

**Вариант 1: Cron job в хост-системе**
```bash
# /etc/cron.daily/backup-postal-db.sh

#!/bin/bash
BACKUP_DIR=/backups/postal
DATE=$(date +%Y%m%d_%H%M%S)

# PostgreSQL backup
docker compose exec -T postgres pg_dump -U email_sender email_sender | gzip > \
  $BACKUP_DIR/postgres_${DATE}.sql.gz

# MariaDB backup
docker compose exec -T mariadb mysqldump -u postal -p${MARIADB_PASSWORD} postal | gzip > \
  $BACKUP_DIR/mariadb_${DATE}.sql.gz

# Удалить старые бэкапы (старше 30 дней)
find $BACKUP_DIR -name "*.sql.gz" -mtime +30 -delete

# Отправить в S3 (опционально)
aws s3 sync $BACKUP_DIR s3://my-bucket/postal-backups/
```

**Вариант 2: Dedicated backup container**
```yaml
# docker-compose.yml
services:
  backup:
    image: databack/mysql-backup:latest
    environment:
      DB_SERVER: mariadb
      DB_USER: postal
      DB_PASS: ${MARIADB_PASSWORD}
      DB_NAMES: postal
      DB_DUMP_FREQ: 1440  # 24 hours
      DB_DUMP_TARGET: s3://my-bucket/postal-backups
    volumes:
      - /etc/ssl/certs:/etc/ssl/certs:ro
```

**Тестирование восстановления**:
```bash
# Восстановление PostgreSQL
gunzip < postgres_backup.sql.gz | \
  docker compose exec -T postgres psql -U email_sender email_sender

# Восстановление MariaDB
gunzip < mariadb_backup.sql.gz | \
  docker compose exec -T mariadb mysql -u postal -p${MARIADB_PASSWORD} postal
```

**Время на исправление**: 2-3 часа
**Зависимости**: S3 bucket (опционально)

---

### 6. ⚠️ Отсутствует мониторинг и alerting

**Приоритет**: 🟡 ВАЖНО
**Категория**: Операционная поддержка
**Риск**: Не заметите проблемы до полного отказа системы

**Где находится**:
```
docker-compose.yml - нет Prometheus, Grafana, Alertmanager
```

**Проблема**:
- Нет метрик (CPU, RAM, disk, queue size)
- Нет алертов (disk full, queue overflow, email failures)
- Нет дашбордов для визуализации

**Как исправить**:

**Шаг 1: Добавить Prometheus**
```yaml
# docker-compose.yml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: email_prometheus
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - frontend

  grafana:
    image: grafana/grafana:latest
    container_name: email_grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3001:3000"
    networks:
      - frontend

  node-exporter:
    image: prom/node-exporter:latest
    container_name: email_node_exporter
    networks:
      - frontend

  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    environment:
      DATA_SOURCE_NAME: "postgresql://email_sender:${POSTGRES_PASSWORD}@postgres:5432/email_sender?sslmode=disable"
    networks:
      - backend
```

**Шаг 2: Конфигурация Prometheus**
```yaml
# config/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'sidekiq'
    static_configs:
      - targets: ['api:3000']
    metrics_path: /metrics
```

**Шаг 3: Добавить Sidekiq metrics**
```ruby
# services/api/Gemfile
gem 'sidekiq_prometheus_exporter'

# config/initializers/sidekiq.rb
require 'sidekiq_prometheus_exporter'

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add SidekiqPrometheus::Middleware
  end
end
```

**Шаг 4: Alerting rules**
```yaml
# config/alerting.yml
groups:
  - name: email_alerts
    rules:
      - alert: HighErrorRate
        expr: rate(email_failed_total[5m]) > 0.1
        for: 5m
        annotations:
          summary: "High email failure rate"

      - alert: QueueOverflow
        expr: sidekiq_queue_size > 10000
        for: 10m
        annotations:
          summary: "Sidekiq queue overflow"

      - alert: DiskSpacelow
        expr: node_filesystem_free_bytes / node_filesystem_size_bytes < 0.1
        for: 5m
        annotations:
          summary: "Disk space below 10%"
```

**Время на исправление**: 6-8 часов
**Зависимости**: Нужно настроить Grafana dashboards

---

### 7. ⚠️ Отсутствуют интеграционные тесты для SMTP Relay

**Приоритет**: 🟡 ВАЖНО
**Категория**: Качество
**Риск**: SMTP Relay может сломаться при изменениях

**Где находится**:
```
services/smtp-relay/ - нет папки tests/ или spec/
```

**Проблема**:
- SMTP Relay не покрыт тестами
- 5 плагинов (1200+ строк кода) без тестов
- Изменения могут сломать функциональность

**Как исправить**:

```javascript
// services/smtp-relay/tests/plugins/smtp_auth.test.js

const { describe, it, expect, beforeEach } = require('@jest/globals');
const smtpAuth = require('../../plugins/smtp_auth');

describe('SMTP Auth Plugin', () => {
  let connection;

  beforeEach(() => {
    connection = {
      transaction: {
        notes: {}
      },
      remote: {
        ip: '127.0.0.1'
      }
    };
  });

  it('should authenticate valid credentials', async () => {
    const result = await smtpAuth.hook_capabilities(
      (retval, msg) => {
        expect(retval).toBe(OK);
        expect(msg).toContain('AUTH PLAIN LOGIN');
      },
      connection
    );
  });

  it('should reject invalid credentials', async () => {
    // test implementation
  });

  it('should apply rate limiting', async () => {
    // test implementation
  });
});
```

**package.json для тестов**:
```json
{
  "scripts": {
    "test": "jest --coverage",
    "test:watch": "jest --watch"
  },
  "devDependencies": {
    "@jest/globals": "^29.0.0",
    "jest": "^29.0.0",
    "supertest": "^6.3.0"
  }
}
```

**Время на исправление**: 8-10 часов
**Зависимости**: Jest framework

---

### 8. ⚠️ Hardcoded rate limit values

**Приоритет**: 🟡 ВАЖНО
**Категория**: Конфигурация
**Риск**: Нельзя изменить rate limits без редеплоя

**Где находится**:
```
services/api/config/initializers/rack_attack.rb:10-15
```

**Проблема**:
```ruby
# Захардкожены значения
Rack::Attack.throttle('api/ip', limit: 10, period: 1.second) do |req|
  req.ip if req.path.start_with?('/api/')
end
```

**Как исправить**:

```ruby
# services/api/config/initializers/rack_attack.rb

# Получать из ENV или SystemConfig
rate_limit = ENV.fetch('API_RATE_LIMIT', 10).to_i
rate_period = ENV.fetch('API_RATE_PERIOD', 1).to_i

Rack::Attack.throttle('api/ip', limit: rate_limit, period: rate_period.seconds) do |req|
  req.ip if req.path.start_with?('/api/')
end

# ИЛИ из базы данных
config = SystemConfig.find_by(key: 'rate_limiting')
if config
  settings = JSON.parse(config.value)
  Rack::Attack.throttle('api/ip', limit: settings['limit'], period: settings['period']) do |req|
    req.ip if req.path.start_with?('/api/')
  end
end
```

**Добавить в .env**:
```bash
# Rate limiting
API_RATE_LIMIT=10
API_RATE_PERIOD=1
API_BURST_LIMIT=50
```

**Время на исправление**: 1-2 часа
**Зависимости**: Нет

---

### 9. ⚠️ Certbot может упасть и не перезапуститься

**Приоритет**: 🟡 ВАЖНО
**Категория**: Надежность
**Риск**: SSL сертификаты не обновятся, сайт станет недоступен

**Где находится**:
```
docker-compose.yml:445-453
```

**Проблема**:
```yaml
certbot:
  image: certbot/certbot:latest
  entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
  # НЕТ restart: unless-stopped
```

**Как исправить**:

```yaml
# docker-compose.yml
services:
  certbot:
    image: certbot/certbot:latest
    container_name: email_certbot
    restart: unless-stopped  # ДОБАВИТЬ ЭТО
    volumes:
      - certbot_certs:/etc/letsencrypt
      - certbot_www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --quiet; sleep 12h & wait $${!}; done;'"
    healthcheck:  # ДОБАВИТЬ healthcheck
      test: ["CMD", "certbot", "certificates"]
      interval: 24h
      timeout: 10s
      retries: 3
    networks:
      - frontend
```

**Дополнительно: уведомления**:
```bash
# Скрипт проверки сертификатов
# /usr/local/bin/check-ssl-expiry.sh

#!/bin/bash
DOMAIN=linenarrow.com
DAYS_BEFORE_EXPIRY=7

EXPIRY_DATE=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | \
  openssl x509 -noout -enddate | cut -d= -f2)

EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

if [ $DAYS_LEFT -lt $DAYS_BEFORE_EXPIRY ]; then
  echo "WARNING: SSL certificate expires in $DAYS_LEFT days!"
  # Отправить email или webhook
fi
```

**Время на исправление**: 1 час
**Зависимости**: Нет

---

## 🟢 СРЕДНИЙ ПРИОРИТЕТ (исправить в течение месяца)

### 10. 🔵 Нет API key expiration

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Безопасность
**Риск**: Скомпрометированный ключ остается активным навсегда

**Где находится**:
```
services/api/app/models/api_key.rb
services/api/db/migrate/001_create_api_keys.rb
```

**Проблема**:
- API ключи не имеют срока действия
- Нет механизма ротации
- Скомпрометированный ключ нельзя автоматически деактивировать

**Как исправить**:

```ruby
# Миграция
class AddExpirationToApiKeys < ActiveRecord::Migration[7.1]
  def change
    add_column :api_keys, :expires_at, :datetime
    add_column :api_keys, :last_rotated_at, :datetime
    add_index :api_keys, :expires_at
  end
end

# Модель
class ApiKey < ApplicationRecord
  scope :active, -> { where(active: true).where('expires_at IS NULL OR expires_at > ?', Time.current) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def expiring_soon?(days = 7)
    expires_at.present? && expires_at < days.days.from_now
  end

  def self.generate(name:, expires_in: 90.days, **options)
    raw_key = SecureRandom.hex(24)
    key_hash = Digest::SHA256.hexdigest(raw_key)

    api_key = create!(
      key_hash: key_hash,
      name: name,
      expires_at: expires_in ? Time.current + expires_in : nil,
      **options
    )

    [api_key, raw_key]
  end

  def rotate!
    new_raw_key = SecureRandom.hex(24)
    new_key_hash = Digest::SHA256.hexdigest(new_raw_key)

    update!(
      key_hash: new_key_hash,
      last_rotated_at: Time.current,
      expires_at: 90.days.from_now
    )

    new_raw_key
  end
end

# Background job для уведомлений
class NotifyExpiringKeysJob < ApplicationJob
  def perform
    ApiKey.active.each do |key|
      if key.expiring_soon?(7)
        # Отправить email владельцу
        ExpirationMailer.key_expiring(key).deliver_later
      end
    end
  end
end
```

**Время на исправление**: 4-5 часов
**Зависимости**: ActionMailer для уведомлений

---

### 11. 🔵 PostgreSQL не имеет репликации

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Надежность / Масштабируемость
**Риск**: При отказе PostgreSQL вся система останавливается

**Где находится**:
```
docker-compose.yml:19-56 (только один инстанс postgres)
```

**Проблема**:
- Единая точка отказа
- Нет read replicas для масштабирования чтения
- Долгое восстановление при отказе

**Как исправить**:

```yaml
# docker-compose.yml
services:
  postgres-primary:
    image: postgres:15-alpine
    container_name: email_postgres_primary
    environment:
      POSTGRES_DB: email_sender
      POSTGRES_USER: email_sender
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_REPLICATION_MODE: master
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: ${POSTGRES_REPLICATION_PASSWORD}
    command: >
      postgres
      -c wal_level=replica
      -c max_wal_senders=3
      -c max_replication_slots=3
      -c hot_standby=on
    volumes:
      - postgres_primary_data:/var/lib/postgresql/data
    networks:
      - backend

  postgres-replica:
    image: postgres:15-alpine
    container_name: email_postgres_replica
    environment:
      POSTGRES_REPLICATION_MODE: slave
      POSTGRES_MASTER_HOST: postgres-primary
      POSTGRES_MASTER_PORT: 5432
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: ${POSTGRES_REPLICATION_PASSWORD}
    depends_on:
      - postgres-primary
    volumes:
      - postgres_replica_data:/var/lib/postgresql/data
    networks:
      - backend
```

**Настройка приложения для чтения с replica**:
```ruby
# config/database.yml
production:
  primary:
    <<: *default
    url: <%= ENV['DATABASE_URL'] %>
  replica:
    <<: *default
    url: <%= ENV['DATABASE_REPLICA_URL'] %>
    replica: true

# В модели
class EmailLog < ApplicationRecord
  connects_to database: { writing: :primary, reading: :replica }
end
```

**Время на исправление**: 6-8 часов
**Зависимости**: Нужно тестирование failover

---

### 12. 🔵 Отсутствует Circuit Breaker

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Надежность
**Риск**: Каскадные отказы при проблемах с Postal

**Где находится**:
```
services/api/app/services/postal_client.rb - прямые HTTP вызовы без защиты
```

**Проблема**:
```ruby
# postal_client.rb
def send_message(payload)
  HTTParty.post(
    "#{@base_url}/api/v1/send/message",
    headers: headers,
    body: payload.to_json
  )
  # Нет защиты от бесконечных retry при падении Postal
end
```

**Как исправить**:

```ruby
# Gemfile
gem 'semian'

# services/api/app/services/postal_client.rb
require 'semian'
require 'semian/httparty'

class PostalClient
  SEMIAN_CONFIG = {
    name: :postal,
    tickets: 5,
    timeout: 2,
    error_threshold: 3,
    error_timeout: 10,
    success_threshold: 2
  }

  def send_message(payload)
    Semian[:postal].acquire do
      HTTParty.post(
        "#{@base_url}/api/v1/send/message",
        headers: headers,
        body: payload.to_json,
        timeout: 5
      )
    end
  rescue Semian::OpenCircuitError
    Rails.logger.error("Circuit breaker open for Postal")
    # Fallback: сохранить в отдельную очередь для retry
    QueuedEmail.create!(payload: payload, retry_after: 1.minute.from_now)
    raise PostalUnavailableError
  end
end
```

**Альтернатива: Shopify Circuit Breaker**:
```ruby
# Gemfile
gem 'circuit_breaker'

# services/api/app/services/postal_client.rb
class PostalClient
  include CircuitBreaker

  circuit_handler do |handler|
    handler.logger = Rails.logger
    handler.failure_threshold = 3
    handler.failure_timeout = 10
    handler.invocation_timeout = 5
  end

  circuit_method :send_message

  def send_message(payload)
    HTTParty.post(...)
  end
end
```

**Время на исправление**: 3-4 часа
**Зависимости**: semian или circuit_breaker gem

---

### 13. 🔵 Нет централизованного логирования

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Операционная поддержка
**Риск**: Сложно отлаживать проблемы в distributed системе

**Где находится**:
```
docker-compose.yml - логи только в volumes, нет централизованного сбора
```

**Проблема**:
- Логи разбросаны по контейнерам
- Нет поиска по логам
- Нет retention policy

**Как исправить**:

**Вариант 1: ELK Stack**
```yaml
# docker-compose.yml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - backend

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.0
    volumes:
      - ./config/logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    depends_on:
      - elasticsearch
    networks:
      - backend

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    networks:
      - frontend

  # Для каждого сервиса добавить
  api:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "service=api"
```

**Вариант 2: Loki (легковеснее)**
```yaml
services:
  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - ./config/loki.yml:/etc/loki/local-config.yaml
      - loki_data:/loki
    networks:
      - backend

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./config/promtail.yml:/etc/promtail/config.yml
    networks:
      - backend
```

**Время на исправление**: 5-6 часов
**Зависимости**: Дополнительные 1-2GB RAM для ELK

---

### 14. 🔵 Нет health check для Sidekiq

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Мониторинг
**Риск**: Sidekiq может зависнуть, но контейнер будет "healthy"

**Где находится**:
```
docker-compose.yml:204-249 (sidekiq service без healthcheck)
```

**Проблема**:
```yaml
sidekiq:
  # НЕТ healthcheck
```

**Как исправить**:

```yaml
# docker-compose.yml
services:
  sidekiq:
    healthcheck:
      test: ["CMD-SHELL", "bundle exec sidekiqmon --json | jq -e '.busy < .concurrency'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

**ИЛИ создать endpoint для health**:
```ruby
# services/api/config/routes.rb
mount Sidekiq::Web => '/sidekiq' if Rails.env.production?

get '/sidekiq/health', to: proc {
  [200, {'Content-Type' => 'application/json'},
   [{ status: 'ok', busy: Sidekiq::Stats.new.workers_size }.to_json]]
}

# docker-compose.yml healthcheck
test: ["CMD", "curl", "-f", "http://localhost:3000/sidekiq/health"]
```

**Время на исправление**: 1-2 часа
**Зависимости**: jq в Docker image или HTTP endpoint

---

### 15. 🔵 Отсутствует retry для webhook delivery

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Надежность
**Риск**: Временные сбои в AMS приведут к потере webhooks

**Где находится**:
```
services/api/app/services/webhook_sender.rb
services/api/app/models/webhook_endpoint.rb
```

**Проблема**:
- WebhookSender делает один запрос
- Если AMS недоступен, webhook теряется
- Нет retry queue

**Как исправить**:

```ruby
# services/api/app/jobs/send_webhook_job.rb
class SendWebhookJob < ApplicationJob
  queue_as :webhooks

  # Exponential backoff: 3s, 30s, 5min, 25min
  retry_on StandardError, wait: :exponentially_longer, attempts: 4

  discard_on ActiveJob::DeserializationError

  def perform(webhook_endpoint_id, event_type, payload)
    endpoint = WebhookEndpoint.find(webhook_endpoint_id)

    return unless endpoint.active?
    return unless endpoint.events.include?(event_type)

    sender = WebhookSender.new(endpoint)
    response = sender.send(event_type, payload)

    if response.success?
      endpoint.record_success
    else
      endpoint.record_failure
      raise WebhookDeliveryError, "Failed with status #{response.code}"
    end
  rescue => e
    Rails.logger.error("Webhook delivery failed: #{e.message}")
    endpoint.record_failure
    raise
  end
end

# В модели
class WebhookEndpoint < ApplicationRecord
  def record_success
    increment!(:successful_deliveries)
    update_column(:last_success_at, Time.current)
  end

  def record_failure
    increment!(:failed_deliveries)
    update_column(:last_failure_at, Time.current)

    # Деактивировать после многих ошибок
    if failed_deliveries > 100 && success_rate < 0.5
      update!(active: false)
      Rails.logger.warn("Webhook endpoint #{id} deactivated due to high failure rate")
    end
  end

  def success_rate
    total = successful_deliveries + failed_deliveries
    return 1.0 if total.zero?
    successful_deliveries.to_f / total
  end
end
```

**Настройка Sidekiq для webhook очереди**:
```yaml
# config/sidekiq.yml
:queues:
  - [critical, 10]
  - [default, 5]
  - [webhooks, 3]
  - [low, 1]
```

**Время на исправление**: 3-4 часа
**Зависимости**: Нет

---

### 16. 🔵 Нет graceful shutdown для Sidekiq jobs

**Приоритет**: 🟢 СРЕДНИЙ
**Категория**: Надежность
**Риск**: Jobs прерываются при рестарте, данные теряются

**Где находится**:
```
services/api/app/jobs/*.rb - все jobs
docker-compose.yml:204 (sidekiq service)
```

**Проблема**:
- При `docker compose restart` Sidekiq получает SIGTERM
- Jobs прерываются немедленно
- Частично обработанные email теряются

**Как исправить**:

```ruby
# services/api/app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  around_perform :handle_shutdown

  private

  def handle_shutdown
    @shutdown = false

    trap('TERM') do
      @shutdown = true
      Rails.logger.warn("#{self.class.name} received TERM, finishing current work...")
    end

    yield
  rescue => e
    raise unless @shutdown
    # Если прервали, не считаем это ошибкой - job вернется в очередь
    Rails.logger.info("#{self.class.name} interrupted by shutdown, will retry")
    retry_job(wait: 5.seconds)
  end
end

# В каждом long-running job добавить проверки
class SendToPostalJob < ApplicationJob
  def perform(email_log_id)
    email_log = EmailLog.find(email_log_id)

    # Разбить на маленькие шаги
    payload = build_payload(email_log)
    return if @shutdown  # Проверка

    response = send_to_postal(payload)
    return if @shutdown  # Проверка

    update_status(email_log, response)
  end
end
```

**Конфигурация Docker**:
```yaml
# docker-compose.yml
sidekiq:
  stop_grace_period: 60s  # Дать 60 секунд на завершение
  command: >
    bundle exec sidekiq
    -C config/sidekiq.yml
    -t 25  # Sidekiq timeout - дать 25 сек на завершение job
```

**Время на исправление**: 2-3 часа
**Зависимости**: Нет

---

## 🔵 НИЗКИЙ ПРИОРИТЕТ (улучшения)

### 17. 📘 Документация на русском языке

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: Документация
**Риск**: Затрудняет международную коллаборацию

**Решение**: Перевести на английский или добавить i18n

**Время**: 10-15 часов

---

### 18. 📘 Нет CI/CD pipeline

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: DevOps
**Риск**: Нет автоматического тестирования при коммитах

**Решение**: Добавить GitHub Actions

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v2
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
      - name: Run tests
        run: |
          bundle install
          bundle exec rspec
```

**Время**: 4-6 часов

---

### 19. 📘 Memory limits могут быть недостаточны

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: Производительность
**Риск**: OOM kills при высоких нагрузках

**Текущие лимиты**:
- API: 400MB
- Sidekiq: 250MB
- PostgreSQL: 350MB

**Решение**: Провести load testing и скорректировать

**Время**: 3-4 часа

---

### 20. 📘 Отсутствует auto-scaling

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: Масштабируемость
**Риск**: Не справится с пиковыми нагрузками

**Решение**: Мигрировать на Kubernetes с HPA (Horizontal Pod Autoscaler)

**Время**: 20-30 часов

---

### 21. 📘 Нет rate limiting для webhook endpoints

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: Защита
**Риск**: DDoS атака на webhook endpoint

**Решение**: Добавить Rack::Attack для webhook paths

**Время**: 1-2 часа

---

### 22. 📘 Hardcoded timeout values

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: Конфигурация
**Риск**: Нельзя настроить timeouts без изменения кода

**Решение**: Вынести в ENV переменные

**Время**: 2-3 часа

---

### 23. 📘 Нет email notifications для критических событий

**Приоритет**: 🔵 НИЗКИЙ
**Категория**: Операционная поддержка
**Риск**: Администратор не узнает о проблемах

**Решение**: Добавить ActionMailer для уведомлений:
- Disk space low
- High error rate
- Service down
- SSL expiring

**Время**: 4-5 часов

---

## 📊 СВОДНАЯ ТАБЛИЦА

| # | Проблема | Приоритет | Время | Сложность |
|---|----------|-----------|-------|-----------|
| 1 | Webhook signature verification | 🔴 КРИТИЧНО | 2-3ч | Средняя |
| 2 | Создать .env файл | 🔴 КРИТИЧНО | 1ч | Низкая |
| 3 | End-to-end тестирование | 🔴 КРИТИЧНО | 4-6ч | Средняя |
| 4 | SMTP rate limiting | 🟡 ВАЖНО | 3-4ч | Средняя |
| 5 | Database backups | 🟡 ВАЖНО | 2-3ч | Низкая |
| 6 | Мониторинг (Prometheus) | 🟡 ВАЖНО | 6-8ч | Высокая |
| 7 | SMTP Relay тесты | 🟡 ВАЖНО | 8-10ч | Высокая |
| 8 | Hardcoded rate limits | 🟡 ВАЖНО | 1-2ч | Низкая |
| 9 | Certbot restart policy | 🟡 ВАЖНО | 1ч | Низкая |
| 10 | API key expiration | 🟢 СРЕДНИЙ | 4-5ч | Средняя |
| 11 | PostgreSQL replication | 🟢 СРЕДНИЙ | 6-8ч | Высокая |
| 12 | Circuit Breaker | 🟢 СРЕДНИЙ | 3-4ч | Средняя |
| 13 | Централизованное логирование | 🟢 СРЕДНИЙ | 5-6ч | Высокая |
| 14 | Sidekiq health check | 🟢 СРЕДНИЙ | 1-2ч | Низкая |
| 15 | Webhook retry logic | 🟢 СРЕДНИЙ | 3-4ч | Средняя |
| 16 | Graceful shutdown | 🟢 СРЕДНИЙ | 2-3ч | Средняя |
| 17-23 | Низкоприоритетные | 🔵 НИЗКИЙ | 45-60ч | Разная |

**Общее время на критичные**: 7-10 часов
**Общее время на важные**: 21-28 часов
**Общее время на средние**: 24-36 часов
**ИТОГО для production-ready**: ~50-75 часов работы

---

## 🎯 ПЛАН ДЕЙСТВИЙ

### Неделя 1: КРИТИЧНЫЕ (MVP)
```
День 1: ✅ Создать .env + генерация секретов (1ч)
День 1: ✅ Исправить webhook signature (3ч)
День 2-3: ✅ End-to-end тестирование (6ч)
```
**Результат**: Система безопасна и протестирована

### Неделя 2: ВАЖНЫЕ (Production-Ready)
```
День 1: ✅ Database backups (3ч)
День 2: ✅ SMTP rate limiting (4ч)
День 3: ✅ Certbot fix + hardcoded values (3ч)
День 4-5: ✅ Мониторинг Prometheus/Grafana (8ч)
```
**Результат**: Система готова к production

### Неделя 3-4: СРЕДНИЕ (Enterprise-Ready)
```
Неделя 3: ✅ Circuit Breaker + Webhook retry + Graceful shutdown (10ч)
Неделя 4: ✅ API key expiration + Sidekiq health (6ч)
```
**Результат**: Система надежная и масштабируемая

---

## 📞 КОНТАКТЫ И ПОДДЕРЖКА

Если нужна помощь с конкретным исправлением, обращайтесь:
- **Критичные проблемы**: немедленно
- **Важные проблемы**: в течение недели
- **Остальные**: по мере возможности

**Все исправления включают**:
- ✅ Код решения
- ✅ Конфигурацию
- ✅ Тесты
- ✅ Документацию

---

**Последнее обновление**: 2026-01-02
**Автор анализа**: Claude (AI Code Analyst)
**Версия документа**: 1.0
