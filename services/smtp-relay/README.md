# SMTP Relay Service

SMTP сервер для приема писем от AMS Enterprise и переадресации в API сервис.

## Архитектура

```
AMS Enterprise --> SMTP Relay (Node.js + Haraka) --> API Service
                       |
                    +---> Tracking Injection
                    +---> Postal Delivery
```

## Основные компоненты

### Server (Node.js + smtp-server)
- `server.js` - основной SMTP сервер с аутентификацией и обработкой писем

### Plugins
- `plugins/smtp_auth.js` - аутентификация через API
- `plugins/parse_email.js` - парсинг входящего письма
- `plugins/rebuild_headers.js` - пересбор заголовков (скрытие AMS)
- `plugins/inject_tracking.js` - внедрение трекинга (ссылки, пиксел)
- `plugins/forward_to_api.js` - отправка в API сервис

## Конфигурация

Переменные окружения:

```bash
# Server
SMTP_RELAY_PORT          # Порт SMTP сервера (по умолчанию 587)
SMTP_AUTH_REQUIRED        # Требовать ли аутентификацию (true/false)
SMTP_RELAY_SECRET        # Секрет для HMAC подписи запросов (опционально)
API_URL                  # URL API сервиса для переадресации

# TLS (STARTTLS)
TLS_CERT_PATH            # Путь к сертификату TLS (опционально)
TLS_KEY_PATH             # Путь к ключу TLS (опционально)

# Rate Limiting
MAX_AUTH_FAILURES         # Максимальное количество неудачных попыток (по умолчанию 5)
AUTH_BLOCK_DURATION        # Длительность блокировки после неудач (миллисекунды, по умолчанию 300000)
```

## Аутентификация

SMTP Relay поддерживает два режима аутентификации:

### 1. HMAC Signature (рекомендуется для production)
Если настроен `SMTP_RELAY_SECRET`, каждый запрос подписывается HMAC-SHA256:

```javascript
const crypto = require('crypto');
const signature = crypto.createHmac('sha256', SMTP_RELAY_SECRET)
  .update(JSON.stringify(payload))
  .digest('hex');
```

API сервис должен верифицировать подпись:

```ruby
expected_signature = OpenSSL::HMAC.hexdigest('SHA256', secret, payload.to_json)
signature == expected_signature
```

### 2. Trusted IP (для разработки)
Если `SMTP_RELAY_SECRET` не настроен, проверяется IP адрес источника:

Доверенные сети:
- `172.16.0.0/12` - Docker bridge
- `10.0.0.0/8` - Docker overlay
- `192.168.0.0/16` - Docker host
- `127.0.0.0/8` - Localhost

## Обработка писем

### Формат payload для API

```json
{
  "envelope": {
    "from": "sender@example.com",
    "to": ["recipient@example.com"]
  },
  "message": {
    "from": "Sender Name <sender@example.com>",
    "to": "Recipient <recipient@example.com>",
    "cc": "cc@example.com",
    "subject": "Email Subject",
    "text": "Plain text body",
    "html": "<html><body>HTML body</body></html>",
    "headers": {
      "message-id": "<message-id@domain.com>",
      "x-campaign-id": "campaign123",
      "x-mailing-id": "mailing456"
    }
  },
  "raw": "Original email in base64",
  "timestamp": "1234567890123"
}
```

### Rate Limiting

- **Per IP**: 100 запросов/минуту
- **Auth Failures**: 5 неудачных попыток → блокировка на 5 минут

### Security Features

1. **TLS/STARTTLS** - шифрование соединения при наличии сертификатов
2. **Max Message Size** - 14MB ограничение размера письма
3. **Bot Detection** - защита от brute force атак
4. **IP Blocking** - автоматическая блокировка подозрительных IP

## Запуск

### Через Docker Compose

```bash
docker compose up -d smtp-relay

# Просмотр логов
docker compose logs -f smtp-relay
```

### Локально

```bash
cd services/smtp-relay
npm install
node server.js
```

## Тестирование

### Тест отправки через SMTP

```bash
# Используя telnet (для базовой проверки)
telnet localhost 587

# Используя swaks (для полного теста)
swaks --server localhost --port 587 \
  --auth-user test_user \
  --auth-password test_pass \
  --from sender@example.com \
  --to recipient@example.com \
  --body "Test email"

# Используя sendmail/postfix (production)
sendmail -S smtp="localhost:587" \
  -f sender@example.com \
  recipient@example.com
```

### Проверка подключения

```bash
# Тест порта
nc -zv localhost 587

# Тест TLS подключения
openssl s_client -connect localhost:587 -starttls smtp
```

## Логи

Формат логов:

```
[session-id] New connection from 192.168.1.100
[session-id] Auth attempt: test_user from 192.168.1.100
[session-id] Auth successful for test_user (rate_limit: 1000)
[session-id] MAIL FROM: sender@example.com
[session-id] RCPT TO: recipient@example.com
[session-id] Receiving message data...
[session-id] Parsed email:
  From: sender@example.com
  To: recipient@example.com
  Subject: Test Email
[session-id] Message forwarded successfully
[session-id] API response: {"status":"queued","message_id":"abc123"}
```

## Troubleshooting

### Проблема: Authentication fails

**Проверьте:**
1. API сервис доступен: `curl http://api:3000/api/v1/health`
2. Учетные данные верны в базе данных
3. HMAC подпись генерируется правильно (если используется)

### Проблема: Connection refused

**Проверьте:**
1. SMTP Relay запущен: `docker compose ps smtp-relay`
2. Порт не занят другим процессом: `netstat -an | grep 587`

### Проблема: TLS не работает

**Проверьте:**
1. Сертификаты существуют: `ls -la /etc/letsencrypt/live/*/`
2. Права доступа на файлы сертификатов: `chmod 600 /etc/letsencrypt/live/*/privkey.pem`
3. Сертификат валиден: `openssl x509 -in cert.pem -noout -dates`

### Проблема: Email не доходит до API

**Проверьте:**
1. API логи: `docker compose logs api`
2. CORS headers (если отправка из браузера)
3. Rate limiting: проверьте не превышены ли лимиты

## Мониторинг

### Health Check

```bash
curl http://localhost:587/health
# Результат: {"status":"healthy","timestamp":"2026-01-19T12:00:00Z"}
```

**Примечание:** SMTP порт не поддерживает HTTP requests, health check доступен только через отдельный endpoint если настроен.

### Метрики для мониторинга

- Количество подключений
- Количество аутентифицированных соединений
- Количество отправленных писем
- Время обработки писем
- Ошибки аутентификации
- Rate limit exceeded счетчик

## Советы по производительности

1. **Используйте connection pooling** для API клиента (keep-alive)
2. **Асинхронная отправка** - не ждите ответа перед обработкой следующего письма
3. **Batch processing** - обрабатывайте несколько писем в одном запросе если возможно
4. **Кэширование** - кэшируйте результаты аутентификации для временного хранения
