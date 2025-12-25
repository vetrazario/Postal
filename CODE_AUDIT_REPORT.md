# ОТЧЕТ ОБ ОШИБКАХ В КОДЕ
## Email Sender Infrastructure - Code Audit

**Дата аудита:** 2025-12-25
**Проверяющий:** Claude Code
**Статус:** Найдено 7 ошибок (3 критических, 2 высоких, 2 средних)

---

## 📋 ОГЛАВЛЕНИЕ

1. [Критические ошибки](#критические-ошибки)
2. [Высокоприоритетные ошибки](#высокоприоритетные-ошибки)
3. [Среднеприоритетные ошибки](#среднеприоритетные-ошибки)
4. [Потенциальные проблемы](#потенциальные-проблемы)
5. [Рекомендации](#рекомендации)

---

## 🔴 КРИТИЧЕСКИЕ ОШИБКИ

### 1. Ключи шифрования не генерируются автоматически

**Файлы:**
- `scripts/pre-install.sh` (строки 44-64)
- `env.example.txt` (строки 53-55)
- `services/api/config/application.rb` (строки 27-29)

**Описание:**

В `env.example.txt` есть заглушки для ключей шифрования:
```bash
ENCRYPTION_PRIMARY_KEY=CHANGE_ME
ENCRYPTION_DETERMINISTIC_KEY=CHANGE_ME
ENCRYPTION_KEY_DERIVATION_SALT=CHANGE_ME
```

Скрипт `pre-install.sh` генерирует все остальные секреты (PostgreSQL, MariaDB, RabbitMQ, SECRET_KEY_BASE, API_KEY, POSTAL_SIGNING_KEY, WEBHOOK_SECRET, DASHBOARD_PASSWORD), **НО НЕ генерирует ключи шифрования**.

При этом Rails требует эти ключи обязательно в `application.rb`:
```ruby
config.active_record.encryption.primary_key = ENV.fetch("ENCRYPTION_PRIMARY_KEY")
config.active_record.encryption.deterministic_key = ENV.fetch("ENCRYPTION_DETERMINISTIC_KEY")
config.active_record.encryption.key_derivation_salt = ENV.fetch("ENCRYPTION_KEY_DERIVATION_SALT")
```

**Проблема "курицы и яйца":**
- Комментарий в `env.example.txt` (строка 52) говорит: `# Генерация: rails db:encryption:init`
- Но Rails НЕ ЗАПУСТИТСЯ, если эти ключи не заданы (ENV.fetch бросит KeyError)
- Получается, нужен Rails для генерации ключей, но Rails не запустится без них

**Последствия:**
- 🔴 **КРИТИЧНО:** Rails API не запустится после установки
- Пользователь увидит ошибку: `KeyError: key not found: "ENCRYPTION_PRIMARY_KEY"`
- Даже если пользователь оставит значения "CHANGE_ME", шифрование будет небезопасным

**Как воспроизвести:**
```bash
# 1. Запустите pre-install.sh
sudo bash scripts/pre-install.sh

# 2. Проверьте .env
grep ENCRYPTION .env
# Вывод:
# ENCRYPTION_PRIMARY_KEY=CHANGE_ME
# ENCRYPTION_DETERMINISTIC_KEY=CHANGE_ME
# ENCRYPTION_KEY_DERIVATION_SALT=CHANGE_ME

# 3. Попробуйте запустить Rails
docker compose up -d api
docker compose logs api
# Увидите: rails aborted! KeyError: key not found: "ENCRYPTION_PRIMARY_KEY" (возможно нет, но значения "CHANGE_ME" небезопасны)
```

**Решение:**

Добавить генерацию ключей шифрования в `pre-install.sh` (после строки 64):
```bash
# Generate encryption keys (for Active Record Encryption)
log_info "Generating encryption keys..."
ENCRYPTION_PRIMARY=$(openssl rand -base64 32)
ENCRYPTION_DETERMINISTIC=$(openssl rand -base64 32)
ENCRYPTION_SALT=$(openssl rand -base64 32)

sed -i "s/ENCRYPTION_PRIMARY_KEY=CHANGE_ME/ENCRYPTION_PRIMARY_KEY=$ENCRYPTION_PRIMARY/" .env
sed -i "s/ENCRYPTION_DETERMINISTIC_KEY=CHANGE_ME/ENCRYPTION_DETERMINISTIC_KEY=$ENCRYPTION_DETERMINISTIC/" .env
sed -i "s/ENCRYPTION_KEY_DERIVATION_SALT=CHANGE_ME/ENCRYPTION_KEY_DERIVATION_SALT=$ENCRYPTION_SALT/" .env

log_success "Encryption keys generated"
```

---

### 2. Конфликт между required_env.rb и dashboard_controller.rb

**Файлы:**
- `services/api/config/initializers/required_env.rb` (строки 9-10)
- `services/api/app/controllers/dashboard_controller.rb` (строки 8-20)

**Описание:**

В `required_env.rb` переменные `DASHBOARD_USERNAME` и `DASHBOARD_PASSWORD` помечены как **ОБЯЗАТЕЛЬНЫЕ**:
```ruby
REQUIRED_ENV = {
  # ...
  'DASHBOARD_USERNAME' => 'Dashboard username',
  'DASHBOARD_PASSWORD' => 'Dashboard password',
  # ...
}.freeze

missing = REQUIRED_ENV.select { |var, _| ENV[var].blank? }

if missing.any?
  message = <<~MSG
    Missing required environment variables:
    #{missing.map { |var, desc| "  - #{var} (#{desc})" }.join("\n")}
  MSG

  if Rails.env.production?
    raise message  # ❌ Rails упадет в production
  elsif !Rails.env.test?
    Rails.logger.error(message)
    warn message
  end
end
```

Но в `dashboard_controller.rb` эти переменные сделаны **ОПЦИОНАЛЬНЫМИ**:
```ruby
if ENV["DASHBOARD_USERNAME"].present? && ENV["DASHBOARD_PASSWORD"].present?
  http_basic_authenticate_with(
    name: ENV.fetch("DASHBOARD_USERNAME"),
    password: ENV.fetch("DASHBOARD_PASSWORD")
  )
else
  # Если не заданы - просто логируем предупреждение
  before_action :warn_no_auth

  def warn_no_auth
    Rails.logger.warn("⚠️  Dashboard accessed WITHOUT authentication!")
  end
end
```

**Конфликт:**
- `required_env.rb` говорит: "Эти переменные обязательны, без них падаем в production"
- `dashboard_controller.rb` говорит: "Эти переменные опциональны, без них просто предупреждение"

**Последствия:**
- 🔴 **КРИТИЧНО:** В production Rails **НЕ ЗАПУСТИТСЯ**, если DASHBOARD_USERNAME/PASSWORD не заданы
- Даже если контроллер готов работать без аутентификации, `required_env.rb` не даст приложению стартовать
- Это делает опциональность в контроллере бесполезной

**Как воспроизвести:**
```bash
# 1. Удалите DASHBOARD_USERNAME/PASSWORD из .env
sed -i '/DASHBOARD_USERNAME/d' .env
sed -i '/DASHBOARD_PASSWORD/d' .env

# 2. Попробуйте запустить Rails в production
RAILS_ENV=production docker compose up api

# Вывод:
# Missing required environment variables:
#   - DASHBOARD_USERNAME (Dashboard username)
#   - DASHBOARD_PASSWORD (Dashboard password)
# rails aborted!
```

**Решение:**

Нужно выбрать одну из стратегий:

**Вариант A:** Убрать DASHBOARD_USERNAME/PASSWORD из списка обязательных в `required_env.rb`:
```ruby
REQUIRED_ENV = {
  'SECRET_KEY_BASE' => 'Rails secret key base',
  'DATABASE_URL' => 'Database connection URL',
  'REDIS_URL' => 'Redis connection URL',
  'ENCRYPTION_PRIMARY_KEY' => 'Encryption primary key',
  'ENCRYPTION_DETERMINISTIC_KEY' => 'Encryption deterministic key',
  'ENCRYPTION_KEY_DERIVATION_SALT' => 'Encryption key derivation salt',
  # УБРАТЬ ЭТИ ДВЕ СТРОКИ:
  # 'DASHBOARD_USERNAME' => 'Dashboard username',
  # 'DASHBOARD_PASSWORD' => 'Dashboard password',
  'POSTAL_SIGNING_KEY' => 'Postal signing key'
}.freeze
```

**Вариант B:** Сделать их обязательными и убрать опциональность из контроллера (не рекомендуется для безопасности):
```ruby
# dashboard_controller.rb
http_basic_authenticate_with(
  name: ENV.fetch("DASHBOARD_USERNAME"),
  password: ENV.fetch("DASHBOARD_PASSWORD")
)
```

**Рекомендация:** Вариант A - убрать из required_env.rb, но всегда генерировать в pre-install.sh (что уже делается).

---

### 3. Postal container command с многострочным sh -c может зависнуть

**Файл:**
- `docker-compose.yml` (строки 281-288)

**Описание:**

Команда запуска Postal использует сложную bash-конструкцию:
```yaml
postal:
  command: >
    sh -c "
      postal initialize-db || true &&
      postal web-server &
      postal smtp-server &
      postal worker &
      wait
    "
```

**Проблемы:**

1. **Использование `|| true` скрывает ошибки:**
   - Если `postal initialize-db` падает с ошибкой (например, не может подключиться к MariaDB), команда продолжится
   - Последующие команды (`web-server`, `smtp-server`, `worker`) могут не работать из-за неинициализированной БД

2. **Background процессы могут не перезапуститься:**
   - Процессы запущены через `&` (в фоне)
   - Если один из процессов упадет, контейнер не перезапустится (так как `wait` ждет всех процессов)
   - Docker не сможет определить, что контейнер в неисправном состоянии

3. **Сложность отладки:**
   - Логи всех процессов смешаны в один поток
   - Невозможно понять, какой именно процесс упал

**Последствия:**
- 🔴 **КРИТИЧНО:** Postal может запуститься с неинициализированной базой данных
- Неясные ошибки при первом запуске ("Access denied", "Table doesn't exist")
- Healthcheck может показывать "healthy", хотя Postal не работает полностью

**Как воспроизвести:**
```bash
# 1. Остановите MariaDB перед запуском Postal
docker compose up -d mariadb
sleep 10
docker compose stop mariadb

# 2. Запустите Postal
docker compose up -d postal

# 3. Проверьте логи
docker compose logs postal

# Вывод:
# postal initialize-db: ERROR - Can't connect to MySQL server
# (но команда продолжится из-за "|| true")
# postal web-server: starting...
# postal smtp-server: starting...
# (оба упадут, так как БД не инициализирована)
```

**Решение:**

Использовать более надежный способ запуска:

**Вариант A:** Отдельная инициализация:
```yaml
# В docker-compose.yml
postal:
  command: ["postal", "run"]  # Упрощенная команда

# Добавить отдельный init service
postal-init:
  image: ghcr.io/postalserver/postal:latest
  depends_on:
    mariadb:
      condition: service_healthy
  command: postal initialize
  restart: "no"
```

**Вариант B:** Использовать entrypoint script:
```bash
#!/bin/bash
# postal-entrypoint.sh
set -e  # Останавливаться при ошибках

echo "Initializing Postal database..."
postal initialize-db

echo "Starting Postal services..."
exec postal run  # Postal имеет встроенный supervisor
```

---

## 🟠 ВЫСОКОПРИОРИТЕТНЫЕ ОШИБКИ

### 4. EmailValidator возвращает ошибку если ALLOWED_SENDER_DOMAINS пуст

**Файл:**
- `services/api/app/services/email_validator.rb` (строки 25-27)

**Описание:**

В методе `validate_sender_domain`:
```ruby
def validate_sender_domain(from_email)
  return error('From email is required') if from_email.blank?

  domain = from_email.split('@').last
  return error('From email domain is invalid') if domain.blank?

  allowed = allowed_domains
  return error('From email domain is not authorized') if allowed.empty?  # ❌ ОШИБКА
  return error('From email domain is not authorized') unless allowed.include?(domain)
  return error('AMS domain not allowed as sender') if domain.downcase.include?('ams')

  success
end

private

def allowed_domains
  ENV.fetch('ALLOWED_SENDER_DOMAINS', '').split(',').map(&:strip)
end
```

**Проблема:**

- Если `ALLOWED_SENDER_DOMAINS` не задан в .env, метод вернет **пустой массив** `[]`
- Проверка `if allowed.empty?` вернет ошибку: **"From email domain is not authorized"**
- Получается, **ВООБЩЕ НИКАКИЕ письма нельзя будет отправить**

**Последствия:**
- 🟠 **ВЫСОКИЙ ПРИОРИТЕТ:** API полностью нефункциональный, если ALLOWED_SENDER_DOMAINS не задан
- Все запросы на `/api/v1/send` вернут ошибку валидации
- Пользователь не поймет, в чем проблема (сообщение об ошибке неясное)

**Как воспроизвести:**
```bash
# 1. Удалите ALLOWED_SENDER_DOMAINS из .env
sed -i '/ALLOWED_SENDER_DOMAINS/d' .env

# 2. Перезапустите API
docker compose restart api

# 3. Попробуйте отправить письмо
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "from_email": "sender@yourdomain.com",
    "subject": "Test"
  }'

# Вывод:
# {"error": {"code": "validation_error", "message": "From email domain is not authorized"}}
```

**Решение:**

Изменить логику валидации:
```ruby
def validate_sender_domain(from_email)
  return error('From email is required') if from_email.blank?

  domain = from_email.split('@').last
  return error('From email domain is invalid') if domain.blank?

  allowed = allowed_domains

  # ИЗМЕНИТЬ ЭТУ ЧАСТЬ:
  if allowed.empty?
    Rails.logger.warn("⚠️  ALLOWED_SENDER_DOMAINS not set - accepting all domains (INSECURE!)")
    # В development/test - разрешить
    # В production - запретить или требовать явную настройку
    if Rails.env.production?
      return error('ALLOWED_SENDER_DOMAINS must be configured in production')
    end
  elsif !allowed.include?(domain)
    return error('From email domain is not authorized')
  end

  return error('AMS domain not allowed as sender') if domain.downcase.include?('ams')

  success
end
```

---

### 5. Tracking handler не обрабатывает зашифрованное поле recipient

**Файл:**
- `services/tracking/lib/tracking_handler.rb` (строки 12-50)

**Описание:**

В `tracking_handler.rb` метод `handle_open` декодирует email из Base64:
```ruby
def handle_open(eid:, cid:, mid:, ip:, user_agent:)
  # Decode parameters
  email = Base64.urlsafe_decode64(eid) rescue nil
  # ...

  # Find email log
  result = conn.exec_params(
    "SELECT id, external_message_id, campaign_id FROM email_logs WHERE external_message_id = $1",
    [message_id]
  )

  # Create tracking event
  conn.exec_params(
    "INSERT INTO tracking_events (...) VALUES ($1, $2, $3, ...)",
    [email_log_id, 'open', { email: email, campaign_id: campaign_id }.to_json, ip, user_agent]
  )
```

**Проблема:**

- В модели `EmailLog` поле `recipient` **зашифровано**:
  ```ruby
  # email_log.rb
  encrypts :recipient, deterministic: true
  ```

- Tracking service работает **напрямую с PostgreSQL** (не через Rails), поэтому:
  - Он **не может прочитать зашифрованное поле** `recipient`
  - Он сохраняет расшифрованный email в `event_data` JSON, но **не может сравнить** его с зашифрованным в БД

- Хотя поиск идет по `external_message_id` (не зашифрованному), в `event_data` сохраняется расшифрованный email, что может быть проблемой безопасности

**Последствия:**
- 🟠 **ВЫСОКИЙ ПРИОРИТЕТ:** Потенциальная утечка PII данных (email адресов)
- В таблице `tracking_events` поле `event_data` содержит **незашифрованные** email адреса
- Это противоречит цели шифрования в `email_logs.recipient`

**Как воспроизвести:**
```bash
# 1. Отправьте письмо и откройте его (кликните на tracking pixel)
# 2. Проверьте tracking_events
docker compose exec postgres psql -U email_sender -d email_sender -c \
  "SELECT event_data FROM tracking_events WHERE event_type = 'open' LIMIT 1;"

# Вывод:
# {"email": "realuser@example.com", "campaign_id": "..."}
# ☝️ Email в открытом виде!
```

**Решение:**

Не сохранять расшифрованный email в `event_data`:
```ruby
def handle_open(eid:, cid:, mid:, ip:, user_agent:)
  # Decode parameters
  email = Base64.urlsafe_decode64(eid) rescue nil  # Только для валидации
  campaign_id = Base64.urlsafe_decode64(cid) rescue nil
  message_id = Base64.urlsafe_decode64(mid) rescue nil

  return { success: false } unless email && campaign_id && message_id

  # Find email log
  conn = PG.connect(@database_url)
  result = conn.exec_params(
    "SELECT id, external_message_id, campaign_id FROM email_logs WHERE external_message_id = $1",
    [message_id]
  )

  return { success: false } if result.rows.empty?

  email_log_id = result.rows.first[0]

  # Create tracking event БЕЗ email в event_data
  conn.exec_params(
    "INSERT INTO tracking_events (...) VALUES ($1, $2, $3, ...)",
    [email_log_id, 'open', { campaign_id: campaign_id }.to_json, ip, user_agent]
    # ☝️ Убрали email из JSON
  )

  { success: true }
end
```

---

## 🟡 СРЕДНЕПРИОРИТЕТНЫЕ ОШИБКИ

### 6. Индекс на зашифрованном поле может быть неэффективным

**Файл:**
- `services/api/db/migrate/003_create_email_logs.rb` (строка 26)

**Описание:**

Миграция создает индекс на поле `recipient`:
```ruby
add_index :email_logs, :recipient
```

Но в модели это поле зашифровано:
```ruby
# email_log.rb
encrypts :recipient, deterministic: true
```

**Проблема:**

- **Детерминированное шифрование** (deterministic: true) означает, что одинаковые значения дадут одинаковый ciphertext
- Это позволяет использовать индекс и делать точные поиски (`WHERE recipient = ?`)
- **НО**: Индекс работает на зашифрованных данных, что может быть менее эффективным

**Последствия:**
- 🟡 **СРЕДНИЙ ПРИОРИТЕТ:** Производительность запросов по `recipient` может быть снижена
- Индекс будет работать, но размер индекса будет больше (из-за шифрования)
- Это может привести к увеличению использования памяти

**Рекомендация:**

Если поиск по `recipient` критичен, рассмотрите один из вариантов:
1. Создать отдельное поле `recipient_hash` для индексации (SHA256)
2. Использовать индекс только для exact match, не для LIKE
3. Принять текущую реализацию, если performance приемлема

Проверьте производительность:
```ruby
# Тест производительности
EmailLog.where(recipient: "test@example.com").explain
```

---

### 7. Missing Gemfile.lock в tracking service

**Файл:**
- `services/tracking/Dockerfile` (строка 23)

**Описание:**

Dockerfile для tracking service содержит:
```dockerfile
COPY Gemfile Gemfile.lock* ./
```

Обратите внимание на `*` после `Gemfile.lock` - это означает "скопировать если существует".

**Проблема:**

- Если `Gemfile.lock` отсутствует (например, в новом клоне репозитория), Docker не упадет с ошибкой
- `bundle install` создаст новый Gemfile.lock **внутри контейнера** с возможно другими версиями gems
- Это может привести к несоответствию версий между разработкой и production

**Последствия:**
- 🟡 **СРЕДНИЙ ПРИОРИТЕТ:** Нестабильность версий gems между окружениями
- Разные разработчики могут получить разные версии зависимостей
- Трудно воспроизвести баги

**Как воспроизвести:**
```bash
# 1. Удалите Gemfile.lock
rm services/tracking/Gemfile.lock

# 2. Соберите образ
docker compose build tracking

# 3. Bundle install создаст новый lock с последними версиями
docker compose run --rm tracking bundle show sidekiq
# Версия может отличаться от ожидаемой
```

**Решение:**

1. **Коммитнуть Gemfile.lock** в репозиторий
2. Изменить Dockerfile:
```dockerfile
# Убрать * - требовать наличие Gemfile.lock
COPY Gemfile Gemfile.lock ./
```

3. Добавить в `.gitignore`:
```
# Не игнорировать Gemfile.lock
!services/*/Gemfile.lock
```

---

## ⚠️ ПОТЕНЦИАЛЬНЫЕ ПРОБЛЕМЫ

### 8. Race condition в docker-entrypoint.sh

**Файл:**
- `services/api/docker-entrypoint.sh` (строки 14-23)

**Описание:**

Скрипт ждет, пока PostgreSQL будет готов принимать подключения:
```bash
max_attempts=30
attempt=0
until timeout 2 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ $attempt -ge $max_attempts ]; then
    echo "Database connection timed out after $max_attempts attempts"
    exit 1
  fi
  echo "Database is unavailable - sleeping (attempt $attempt/$max_attempts)"
  sleep 2
done
echo "Database is ready"
```

**Потенциальная проблема:**

- Проверка `/dev/tcp/$DB_HOST/$DB_PORT` только проверяет, что порт **открыт**
- Это **НЕ ГАРАНТИРУЕТ**, что PostgreSQL готов принимать запросы (может быть в процессе инициализации)
- После успеха есть `sleep 3` (строка 26), но это **не надежно** для медленных серверов

**Последствия:**
- ⚠️ Возможны ошибки миграции при первом запуске на медленных серверах
- Редко, но может произойти: "FATAL: database system is starting up"

**Рекомендация:**

Использовать более надежную проверку:
```bash
# Вместо /dev/tcp проверки, использовать pg_isready
until PGPASSWORD=$DB_PASSWORD pg_isready -h $DB_HOST -p $DB_PORT -U email_sender; do
  attempt=$((attempt + 1))
  if [ $attempt -ge $max_attempts ]; then
    echo "Database not ready after $max_attempts attempts"
    exit 1
  fi
  echo "Waiting for database (attempt $attempt/$max_attempts)..."
  sleep 2
done
echo "Database is ready!"
```

---

### 9. Отсутствие валидации URL в TrackingInjector

**Файл:**
- `services/api/app/services/tracking_injector.rb` (строки 9-35)

**Описание:**

Метод `inject_tracking_links` заменяет все ссылки на tracking URLs:
```ruby
html.gsub(/<a\s+([^>]*\s+)?href=["']([^"']+)["']([^>]*)>/i) do |match|
  attrs_before = $1 || ""
  original_url = $2
  attrs_after = $3 || ""

  # Skip links that already use tracking domain
  next match if original_url.include?(domain)

  # Skip mailto: links
  next match if original_url.start_with?("mailto:")

  # Skip anchor links
  next match if original_url.start_with?("#")

  # Skip unsubscribe links
  next match if original_url.include?("unsubscribe")

  # Encode original URL
  encoded_url = Base64.urlsafe_encode64(original_url)

  # Build tracking URL
  tracking_url = "https://#{domain}/track/c?url=#{encoded_url}&..."

  "<a #{attrs_before}href=\"#{tracking_url}\"#{attrs_after}>"
end
```

**Потенциальная проблема:**

- Нет валидации формата URL перед кодированием
- Может закодировать невалидные URLs (например, `javascript:alert('XSS')`)
- Может закодировать относительные пути (например, `/page`)

**Последствия:**
- ⚠️ Возможны broken links после tracking injection
- Пользователь кликает на ссылку → перенаправляется на `/track/c?url=...` → декодируется невалидный URL → ошибка

**Рекомендация:**

Добавить валидацию:
```ruby
# Skip invalid URLs
next match unless original_url =~ URI::regexp(['http', 'https'])

# Or более строгая проверка
begin
  uri = URI.parse(original_url)
  next match unless uri.absolute? && uri.scheme.in?(['http', 'https'])
rescue URI::InvalidURIError
  next match
end
```

---

## 📊 СВОДНАЯ ТАБЛИЦА

| # | Ошибка | Файл | Строки | Приоритет | Влияние |
|---|--------|------|--------|-----------|---------|
| 1 | Ключи шифрования не генерируются | `scripts/pre-install.sh` | 44-64 | 🔴 Критичный | Rails не запустится |
| 2 | Конфликт required_env и dashboard_controller | `required_env.rb` | 9-10 | 🔴 Критичный | App не запустится в prod |
| 3 | Postal command с || true и & | `docker-compose.yml` | 281-288 | 🔴 Критичный | Postal может не работать |
| 4 | EmailValidator падает если нет ALLOWED_SENDER_DOMAINS | `email_validator.rb` | 25-27 | 🟠 Высокий | API не работает |
| 5 | Tracking handler сохраняет незашифрованный email | `tracking_handler.rb` | 38 | 🟠 Высокий | Утечка PII |
| 6 | Индекс на зашифрованном поле | `003_create_email_logs.rb` | 26 | 🟡 Средний | Производительность |
| 7 | Отсутствует Gemfile.lock в tracking | `tracking/Dockerfile` | 23 | 🟡 Средний | Нестабильность версий |
| 8 | Race condition в entrypoint | `docker-entrypoint.sh` | 14-23 | ⚠️ Низкий | Редкие ошибки миграций |
| 9 | Нет валидации URL в tracking injector | `tracking_injector.rb` | 10-28 | ⚠️ Низкий | Broken links |

---

## ✅ РЕКОМЕНДАЦИИ

### Приоритет 1 (Исправить немедленно):

1. ✅ Добавить генерацию ключей шифрования в `pre-install.sh`
2. ✅ Убрать DASHBOARD_USERNAME/PASSWORD из REQUIRED_ENV в `required_env.rb`
3. ✅ Упростить команду запуска Postal в `docker-compose.yml`

### Приоритет 2 (Исправить в ближайшее время):

4. ✅ Обработать случай пустого ALLOWED_SENDER_DOMAINS в `email_validator.rb`
5. ✅ Не сохранять незашифрованный email в tracking_events

### Приоритет 3 (Рассмотреть для улучшения):

6. ⚪ Проверить производительность индекса на зашифрованном поле
7. ⚪ Добавить Gemfile.lock для tracking service
8. ⚪ Улучшить проверку готовности PostgreSQL
9. ⚪ Добавить валидацию URL в tracking injector

---

## 📝 ДОПОЛНИТЕЛЬНЫЕ ЗАМЕЧАНИЯ

### Хорошие практики, найденные в коде:

✅ Использование параметризованных запросов (защита от SQL injection)
✅ HTTP Basic Authentication для Dashboard
✅ Шифрование PII данных (recipient email)
✅ Rate limiting через Rack::Attack
✅ Healthcheck endpoints для всех сервисов
✅ Proper error handling в большинстве мест
✅ Background jobs через Sidekiq
✅ Разделение concerns (services, jobs, validators)

### Области для улучшения:

⚠️ Добавить тесты (RSpec) для критичных компонентов
⚠️ Добавить мониторинг (Sentry уже подключен, но нужна настройка)
⚠️ Логирование можно улучшить (structured logging)
⚠️ Добавить метрики (Prometheus/StatsD)
⚠️ CI/CD pipeline (GitHub Actions)

---

**Конец отчета**

Дата: 2025-12-25
Версия: 1.0
