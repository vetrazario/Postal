# Security Guide

## Обзор угроз

Email-система — привлекательная цель для атак:

| Угроза | Последствия | Приоритет |
|--------|-------------|-----------|
| API ключ украден | Спам через ваш сервер, блеклист | **Критический** |
| SQL Injection | Утечка данных, удаление БД | **Критический** |
| Unauthorized access | Доступ к логам, PII | **Высокий** |
| DDoS | Сервис недоступен | **Средний** |
| Информация в логах | Утечка PII | **Средний** |

---

## 1. Аутентификация API

### 1.1 Генерация API ключей

```ruby
# ПРАВИЛЬНО: 48 символов hex (192 бит энтропии)
api_key = SecureRandom.hex(24)
# Пример: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"

# НЕПРАВИЛЬНО: короткие ключи
api_key = SecureRandom.hex(8)  # Только 64 бита - brute force возможен!
```

### 1.2 Хранение ключей

```ruby
# ПРАВИЛЬНО: хранить только хеш
class ApiKey < ApplicationRecord
  before_create :hash_key
  
  attr_accessor :raw_key  # Только для отображения при создании
  
  def self.authenticate(key)
    find_by(key_hash: Digest::SHA256.hexdigest(key), active: true)
  end
  
  private
  
  def hash_key
    self.raw_key = SecureRandom.hex(24)
    self.key_hash = Digest::SHA256.hexdigest(raw_key)
  end
end

# НЕПРАВИЛЬНО: хранить ключ в открытом виде
# key_hash = api_key  # НЕТ!
```

### 1.3 Проверка ключа

```ruby
# ПРАВИЛЬНО: timing-safe сравнение
def authenticate_api_key
  key = request.headers["Authorization"]&.gsub(/^Bearer /, "")
  
  return render_unauthorized unless key.present?
  return render_unauthorized unless key.match?(/\A[a-f0-9]{48}\z/)
  
  @api_key = ApiKey.authenticate(key)
  return render_unauthorized unless @api_key
  
  @api_key.touch(:last_used_at)
end

# НЕПРАВИЛЬНО: утечка информации
def bad_authenticate
  key = params[:api_key]
  api_key = ApiKey.find_by(key_hash: key)
  
  if api_key.nil?
    render json: { error: "Key not found" }  # Утечка: ключ не существует
  elsif !api_key.active?
    render json: { error: "Key disabled" }   # Утечка: ключ существует, но отключён
  end
end
```

### 1.4 Rate Limiting

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Лимит по API ключу
  throttle("api/key", limit: 100, period: 1.second) do |req|
    if req.path.start_with?("/api/")
      req.env["HTTP_AUTHORIZATION"]&.gsub(/^Bearer /, "")
    end
  end
  
  # Лимит по IP (защита от брутфорса ключей)
  throttle("api/ip", limit: 10, period: 1.second) do |req|
    if req.path.start_with?("/api/")
      req.ip
    end
  end
  
  # Блокировка после неудачных попыток
  blocklist("fail2ban") do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 5, findtime: 1.minute, bantime: 1.hour) do
      req.path.start_with?("/api/") && req.env["warden"]&.user.nil?
    end
  end
end
```

---

## 2. Защита от инъекций

### 2.1 SQL Injection

```ruby
# ПРАВИЛЬНО: параметризованные запросы
EmailLog.where(campaign_id: params[:campaign_id])
EmailLog.where("created_at > ?", params[:date])

# ПРАВИЛЬНО: ActiveRecord
api_key = ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(key))

# НЕПРАВИЛЬНО: конкатенация строк
EmailLog.where("campaign_id = '#{params[:campaign_id]}'")  # SQL INJECTION!
```

### 2.2 Command Injection

```ruby
# ПРАВИЛЬНО: никогда не выполнять пользовательский ввод
# Если нужно выполнить команду:
system("postal", "send", "--to", Shellwords.escape(email))

# НЕПРАВИЛЬНО: 
system("postal send --to #{email}")  # COMMAND INJECTION!
`postal send --to #{email}`          # COMMAND INJECTION!
```

### 2.3 Template Injection

```ruby
# ПРАВИЛЬНО: использовать Liquid (песочница)
template = Liquid::Template.parse(html_template)
rendered = template.render(variables)

# НЕПРАВИЛЬНО: использовать ERB для пользовательских шаблонов
ERB.new(user_template).result(binding)  # RCE VULNERABILITY!
```

---

## 3. Защита данных

### 3.1 Шифрование PII

```ruby
# config/application.rb
config.active_record.encryption.primary_key = ENV["ENCRYPTION_PRIMARY_KEY"]
config.active_record.encryption.deterministic_key = ENV["ENCRYPTION_DETERMINISTIC_KEY"]
config.active_record.encryption.key_derivation_salt = ENV["ENCRYPTION_KEY_DERIVATION_SALT"]

# app/models/email_log.rb
class EmailLog < ApplicationRecord
  # Шифрование email получателя
  encrypts :recipient, deterministic: true
  
  # Маскированная версия для логов
  def recipient_masked
    return nil unless recipient
    local, domain = recipient.split("@")
    "#{local[0]}***@#{domain}"
  end
end
```

### 3.2 Безопасное логирование

```ruby
# ПРАВИЛЬНО: маскировать PII
Rails.logger.info("Sending email to #{email_log.recipient_masked}")
Rails.logger.info("Campaign: #{campaign_id}, Status: #{status}")

# НЕПРАВИЛЬНО: логировать PII
Rails.logger.info("Sending email to #{recipient}")  # УТЕЧКА!
Rails.logger.info("Request: #{request.body.read}")  # УТЕЧКА!
```

### 3.3 Фильтрация параметров

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password,
  :api_key,
  :recipient,
  :email,
  :variables  # Могут содержать PII
]
```

---

## 4. Сетевая безопасность

### 4.1 TLS

```nginx
# nginx.conf - только TLS 1.2 и 1.3
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

# HSTS
add_header Strict-Transport-Security "max-age=63072000" always;
```

### 4.2 Firewall

```bash
# ufw (Ubuntu)
ufw default deny incoming
ufw default allow outgoing

# SSH (изменить порт!)
ufw allow 22/tcp  # или нестандартный порт

# HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# SMTP outbound (уже разрешён в outgoing)

# НЕ открывать:
# - PostgreSQL (5432)
# - Redis (6379)
# - RabbitMQ (5672)
# - MariaDB (3306)
```

### 4.3 Docker network isolation

```yaml
# docker-compose.yml
services:
  api:
    networks:
      - frontend
      - backend
  
  postgres:
    networks:
      - backend  # Только внутренняя сеть!
  
  nginx:
    networks:
      - frontend
    ports:
      - "443:443"  # Только nginx доступен снаружи

networks:
  frontend:
  backend:
    internal: true  # Изолированная сеть
```

---

## 5. Email безопасность

### 5.1 Валидация отправителя

```ruby
class EmailValidator
  ALLOWED_DOMAINS = ENV["ALLOWED_SENDER_DOMAINS"].split(",")
  
  def self.validate_sender(from_email)
    domain = from_email.split("@").last
    
    unless ALLOWED_DOMAINS.include?(domain)
      raise ValidationError, "Sender domain not allowed: #{domain}"
    end
  end
end
```

### 5.2 SPF/DKIM/DMARC

```
# SPF (строгий)
v=spf1 ip4:YOUR_IP -all

# DKIM (2048 bit минимум)
# Генерируется Postal

# DMARC (reject политика)
v=DMARC1; p=reject; sp=reject; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; fo=1
```

### 5.3 Валидация получателя

```ruby
class RecipientValidator
  # RFC 5321 email validation
  EMAIL_REGEX = /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\z/
  
  # Запрещённые домены (honeypots, traps)
  BLACKLISTED_DOMAINS = [
    "spamtrap.example.com",
    "honeypot.example.com"
  ]
  
  def self.validate(email)
    return false unless email.match?(EMAIL_REGEX)
    return false if email.length > 254
    
    domain = email.split("@").last.downcase
    return false if BLACKLISTED_DOMAINS.include?(domain)
    
    true
  end
end
```

---

## 6. Webhook безопасность

### 6.1 Подпись исходящих webhooks

```ruby
class WebhookSender
  def self.send(url:, payload:)
    timestamp = Time.now.to_i
    signature = generate_signature(payload, timestamp)
    
    response = HTTParty.post(url,
      body: payload.to_json,
      headers: {
        "Content-Type" => "application/json",
        "X-Timestamp" => timestamp.to_s,
        "X-Signature" => signature
      }
    )
  end
  
  private
  
  def self.generate_signature(payload, timestamp)
    data = "#{timestamp}.#{payload.to_json}"
    OpenSSL::HMAC.hexdigest("SHA256", ENV["WEBHOOK_SECRET"], data)
  end
end
```

### 6.2 Проверка входящих webhooks (от Postal)

```ruby
class WebhooksController < ApplicationController
  before_action :verify_postal_signature
  
  private
  
  def verify_postal_signature
    signature = request.headers["X-Postal-Signature"]
    payload = request.body.read
    
    expected = OpenSSL::HMAC.hexdigest("SHA256", ENV["POSTAL_WEBHOOK_KEY"], payload)
    
    unless ActiveSupport::SecurityUtils.secure_compare(signature, "sha256=#{expected}")
      render json: { error: "Invalid signature" }, status: :unauthorized
    end
  end
end
```

---

## 7. Секреты

### 7.1 Где хранить

| Секрет | Где хранить | Как передавать |
|--------|-------------|----------------|
| API ключи | PostgreSQL (хеш) | Authorization header |
| DB passwords | .env файл | Environment variables |
| Encryption keys | .env файл | Environment variables |
| DKIM private key | Postal volume | Не передаётся |

### 7.2 Генерация секретов

```bash
# PostgreSQL пароль (32 символа hex)
openssl rand -hex 16

# Rails secret key (64 символа hex)
openssl rand -hex 32

# API ключ (48 символов hex)
openssl rand -hex 24

# Encryption keys
rails db:encryption:init
```

### 7.3 Ротация секретов

```bash
# 1. Генерировать новый секрет
NEW_KEY=$(openssl rand -hex 24)

# 2. Добавить в систему (не удаляя старый)
# 3. Обновить клиентов
# 4. Деактивировать старый ключ
# 5. Удалить старый ключ
```

---

## 8. Аудит и мониторинг

### 8.1 Что логировать

```ruby
# Обязательно логировать:
Rails.logger.info({
  event: "api_request",
  api_key_id: @api_key.id,
  endpoint: request.path,
  method: request.method,
  ip: request.ip,
  user_agent: request.user_agent,
  status: response.status,
  duration_ms: elapsed_time
}.to_json)

# Логировать при подозрительной активности:
Rails.logger.warn({
  event: "suspicious_activity",
  type: "rate_limit_exceeded",
  ip: request.ip,
  api_key_id: @api_key&.id
}.to_json)
```

### 8.2 Алерты

| Событие | Порог | Действие |
|---------|-------|----------|
| Неудачные авторизации | >10/мин с одного IP | Временная блокировка |
| Rate limit exceeded | >100/мин | Уведомление |
| Bounce rate | >5% | Приостановка отправки |
| Error rate | >1% | Уведомление |
| Disk usage | >80% | Уведомление |

### 8.3 Fail2Ban конфигурация

```ini
# /etc/fail2ban/jail.d/email-sender.conf
[email-sender-api]
enabled = true
port = 443
filter = email-sender-api
logpath = /opt/email-sender/logs/api.log
maxretry = 5
findtime = 60
bantime = 3600

# /etc/fail2ban/filter.d/email-sender-api.conf
[Definition]
failregex = ^.*"event":"auth_failed".*"ip":"<HOST>".*$
ignoreregex =
```

---

## 9. Чеклист безопасности

### Перед деплоем

- [ ] Все пароли сгенерированы случайным образом
- [ ] .env файл имеет права 600
- [ ] SSH доступ только по ключам
- [ ] SSH порт изменён
- [ ] Firewall настроен
- [ ] SSL сертификат установлен
- [ ] HSTS включён

### После деплоя

- [ ] Health check работает
- [ ] Rate limiting работает
- [ ] Неудачные авторизации логируются
- [ ] Бэкапы настроены
- [ ] Мониторинг настроен
- [ ] Алерты настроены

### Регулярно

- [ ] Обновление зависимостей (еженедельно)
- [ ] Проверка логов (ежедневно)
- [ ] Проверка бэкапов (еженедельно)
- [ ] Ротация ключей (ежемесячно)
- [ ] Аудит безопасности (ежеквартально)

---

## 10. Incident Response

### При утечке API ключа

1. **Немедленно**: деактивировать ключ
   ```sql
   UPDATE api_keys SET active = false WHERE key_hash = 'xxx';
   ```

2. Проверить логи на подозрительную активность
3. Сгенерировать новый ключ
4. Уведомить клиента
5. Провести расследование

### При DDoS атаке

1. Включить усиленный rate limiting
2. Добавить IP в чёрный список (если определён)
3. Включить Cloudflare/DDoS защиту
4. Масштабировать инфраструктуру

### При компрометации сервера

1. **Немедленно**: изолировать сервер (отключить от сети)
2. Сделать snapshot для расследования
3. Развернуть новый сервер
4. Ротировать ВСЕ секреты
5. Уведомить затронутых пользователей
6. Провести расследование

