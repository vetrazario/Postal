# API Specification

## Общие правила

### Base URL

```
https://{domain}/api/v1/
```

### Аутентификация

Все запросы (кроме `/health`) требуют заголовок:

```
Authorization: Bearer {api_key}
```

**Формат API ключа:** 48 символов hex (24 байта)

**Пример:** `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6`

### Content-Type

Все запросы и ответы в JSON:

```
Content-Type: application/json
```

### Коды ответов

| Код | Значение | Когда используется |
|-----|----------|-------------------|
| `200` | OK | Успешный GET запрос |
| `201` | Created | Успешный POST (создание) |
| `202` | Accepted | Запрос принят в обработку (асинхронно) |
| `400` | Bad Request | Неверный формат данных |
| `401` | Unauthorized | Неверный или отсутствует API ключ |
| `403` | Forbidden | Нет прав на операцию |
| `404` | Not Found | Ресурс не найден |
| `422` | Unprocessable Entity | Данные не прошли валидацию |
| `429` | Too Many Requests | Превышен rate limit |
| `500` | Internal Server Error | Ошибка сервера |
| `503` | Service Unavailable | Сервис временно недоступен |

### Формат ошибки

```json
{
  "error": {
    "code": "validation_error",
    "message": "Recipient email is invalid",
    "details": {
      "field": "recipient",
      "value": "invalid-email",
      "constraint": "email_format"
    }
  },
  "request_id": "req_abc123def456"
}
```

---

## Endpoints

### 1. POST /api/v1/send

Отправка одного письма.

#### Request

```http
POST /api/v1/send HTTP/1.1
Host: send1.example.com
Authorization: Bearer a1b2c3d4e5f6...
Content-Type: application/json

{
  "recipient": "user@gmail.com",
  "template_id": "promo_welcome",
  "from_name": "Kate Roleson",
  "from_email": "kate@domain.com",
  "subject": "Welcome Gift for You",
  "variables": {
    "name": "John",
    "promo_code": "SPIN50",
    "bonus_amount": "100"
  },
  "tracking": {
    "campaign_id": "camp_12345",
    "message_id": "msg_67890",
    "affiliate_id": "aff_abc123",
    "recipient_id": "rcpt_xyz789"
  },
  "options": {
    "priority": "normal",
    "tags": ["welcome", "promo"],
    "send_at": null
  }
}
```

#### Параметры

| Поле | Тип | Обязательно | Описание |
|------|-----|-------------|----------|
| `recipient` | string | ✅ | Email получателя |
| `template_id` | string | ✅ | ID шаблона |
| `from_name` | string | ✅ | Имя отправителя |
| `from_email` | string | ✅ | Email отправителя (должен быть в списке разрешённых доменов) |
| `subject` | string | ✅ | Тема письма (может содержать Liquid переменные) |
| `variables` | object | ❌ | Переменные для шаблона |
| `tracking` | object | ✅ | Данные для трекинга |
| `tracking.campaign_id` | string | ✅ | ID кампании |
| `tracking.message_id` | string | ✅ | Уникальный ID сообщения от AMS |
| `tracking.affiliate_id` | string | ❌ | ID партнёра |
| `tracking.recipient_id` | string | ❌ | ID получателя в AMS |
| `options` | object | ❌ | Дополнительные опции |
| `options.priority` | string | ❌ | `"high"`, `"normal"`, `"low"`. Default: `"normal"` |
| `options.tags` | array | ❌ | Теги для группировки |
| `options.send_at` | string (ISO 8601) | ❌ | Отложенная отправка. `null` = немедленно |

#### Response (202 Accepted)

```json
{
  "status": "queued",
  "message_id": "local_abc123def456",
  "external_message_id": "msg_67890",
  "estimated_send_time": "2025-12-14T18:30:00Z",
  "request_id": "req_xyz789"
}
```

#### Ошибки

**400 Bad Request** — неверный JSON:
```json
{
  "error": {
    "code": "invalid_json",
    "message": "Request body is not valid JSON"
  }
}
```

**401 Unauthorized** — неверный API ключ:
```json
{
  "error": {
    "code": "invalid_api_key",
    "message": "API key is invalid or expired"
  }
}
```

**422 Unprocessable Entity** — ошибка валидации:
```json
{
  "error": {
    "code": "validation_error",
    "message": "Validation failed",
    "details": [
      {
        "field": "recipient",
        "message": "is not a valid email address"
      },
      {
        "field": "from_email",
        "message": "domain is not authorized"
      }
    ]
  }
}
```

**429 Too Many Requests** — превышен лимит:
```json
{
  "error": {
    "code": "rate_limit_exceeded",
    "message": "Rate limit exceeded. Try again in 60 seconds.",
    "retry_after": 60
  }
}
```

---

### 2. POST /api/v1/batch

Пакетная отправка (до 100 писем за раз).

#### Request

```http
POST /api/v1/batch HTTP/1.1
Host: send1.example.com
Authorization: Bearer a1b2c3d4e5f6...
Content-Type: application/json

{
  "template_id": "promo_welcome",
  "from_name": "Kate Roleson",
  "from_email": "kate@domain.com",
  "subject": "Welcome Gift for {{ name }}",
  "campaign_id": "camp_12345",
  "messages": [
    {
      "recipient": "user1@gmail.com",
      "message_id": "msg_001",
      "variables": {
        "name": "John",
        "promo_code": "CODE1"
      }
    },
    {
      "recipient": "user2@gmail.com",
      "message_id": "msg_002",
      "variables": {
        "name": "Jane",
        "promo_code": "CODE2"
      }
    }
  ]
}
```

#### Параметры

| Поле | Тип | Обязательно | Описание |
|------|-----|-------------|----------|
| `template_id` | string | ✅ | ID шаблона (общий для всех) |
| `from_name` | string | ✅ | Имя отправителя |
| `from_email` | string | ✅ | Email отправителя |
| `subject` | string | ✅ | Тема (может содержать переменные) |
| `campaign_id` | string | ✅ | ID кампании |
| `messages` | array | ✅ | Массив сообщений (max 100) |
| `messages[].recipient` | string | ✅ | Email получателя |
| `messages[].message_id` | string | ✅ | Уникальный ID от AMS |
| `messages[].variables` | object | ❌ | Переменные для этого получателя |

#### Response (202 Accepted)

```json
{
  "status": "queued",
  "batch_id": "batch_abc123",
  "total": 2,
  "queued": 2,
  "failed": 0,
  "results": [
    {
      "recipient": "user1@gmail.com",
      "message_id": "msg_001",
      "local_id": "local_001",
      "status": "queued"
    },
    {
      "recipient": "user2@gmail.com",
      "message_id": "msg_002",
      "local_id": "local_002",
      "status": "queued"
    }
  ]
}
```

#### Частичный успех

Если часть сообщений не прошла валидацию:

```json
{
  "status": "partial",
  "batch_id": "batch_abc123",
  "total": 3,
  "queued": 2,
  "failed": 1,
  "results": [
    {
      "recipient": "user1@gmail.com",
      "message_id": "msg_001",
      "local_id": "local_001",
      "status": "queued"
    },
    {
      "recipient": "invalid-email",
      "message_id": "msg_002",
      "status": "failed",
      "error": "Invalid email format"
    },
    {
      "recipient": "user3@gmail.com",
      "message_id": "msg_003",
      "local_id": "local_003",
      "status": "queued"
    }
  ]
}
```

---

### 3. GET /api/v1/status/{message_id}

Получение статуса сообщения.

#### Request

```http
GET /api/v1/status/msg_67890 HTTP/1.1
Host: send1.example.com
Authorization: Bearer a1b2c3d4e5f6...
```

#### Response (200 OK)

```json
{
  "message_id": "msg_67890",
  "local_id": "local_abc123",
  "status": "delivered",
  "recipient": "u***@gmail.com",
  "created_at": "2025-12-14T18:00:00Z",
  "sent_at": "2025-12-14T18:00:05Z",
  "delivered_at": "2025-12-14T18:00:07Z",
  "events": [
    {
      "type": "queued",
      "timestamp": "2025-12-14T18:00:00Z"
    },
    {
      "type": "sent",
      "timestamp": "2025-12-14T18:00:05Z"
    },
    {
      "type": "delivered",
      "timestamp": "2025-12-14T18:00:07Z"
    },
    {
      "type": "opened",
      "timestamp": "2025-12-14T18:15:23Z",
      "ip": "1.2.3.4",
      "user_agent": "Mozilla/5.0..."
    }
  ]
}
```

#### Возможные статусы

| Статус | Описание |
|--------|----------|
| `queued` | В очереди на обработку |
| `processing` | Собирается письмо |
| `sent` | Отправлено в Postal |
| `delivered` | Доставлено получателю |
| `bounced` | Отклонено (hard/soft bounce) |
| `failed` | Ошибка отправки |
| `complained` | Жалоба на спам |

---

### 4. GET /api/v1/health

Проверка состояния сервера. **Не требует авторизации.**

#### Request

```http
GET /api/v1/health HTTP/1.1
Host: send1.example.com
```

#### Response (200 OK) — здоровый сервер

```json
{
  "status": "healthy",
  "timestamp": "2025-12-14T18:30:00Z",
  "version": "1.0.0",
  "components": {
    "database": "ok",
    "redis": "ok",
    "sidekiq": "ok",
    "postal": "ok"
  },
  "queues": {
    "default": 0,
    "mailers": 12,
    "critical": 0
  },
  "stats": {
    "sent_today": 15420,
    "limit_today": 50000,
    "available": 34580,
    "bounce_rate": 0.5,
    "error_rate": 0.1
  }
}
```

#### Response (503 Service Unavailable) — проблемы

```json
{
  "status": "unhealthy",
  "timestamp": "2025-12-14T18:30:00Z",
  "version": "1.0.0",
  "components": {
    "database": "ok",
    "redis": "error",
    "sidekiq": "degraded",
    "postal": "ok"
  },
  "error": "Redis connection refused"
}
```

---

### 5. GET /api/v1/stats

Статистика сервера за период.

#### Request

```http
GET /api/v1/stats?period=today HTTP/1.1
Host: send1.example.com
Authorization: Bearer a1b2c3d4e5f6...
```

#### Query параметры

| Параметр | Тип | Обязательно | Описание |
|----------|-----|-------------|----------|
| `period` | string | ❌ | `today`, `yesterday`, `week`, `month`. Default: `today` |
| `campaign_id` | string | ❌ | Фильтр по кампании |

#### Response (200 OK)

```json
{
  "period": "today",
  "date_from": "2025-12-14T00:00:00Z",
  "date_to": "2025-12-14T23:59:59Z",
  "summary": {
    "total_sent": 15420,
    "delivered": 15200,
    "bounced": 120,
    "failed": 100,
    "opened": 3800,
    "clicked": 450,
    "complained": 5
  },
  "rates": {
    "delivery_rate": 98.57,
    "bounce_rate": 0.78,
    "open_rate": 25.0,
    "click_rate": 2.96,
    "complaint_rate": 0.03
  },
  "hourly": [
    {"hour": 0, "sent": 500, "delivered": 495},
    {"hour": 1, "sent": 450, "delivered": 448},
    ...
  ]
}
```

---

### 6. POST /api/v1/templates

Загрузка/обновление шаблона.

#### Request

```http
POST /api/v1/templates HTTP/1.1
Host: send1.example.com
Authorization: Bearer a1b2c3d4e5f6...
Content-Type: application/json

{
  "template_id": "promo_welcome",
  "name": "Welcome Promo Email",
  "subject_template": "Welcome Gift for {{ name }}",
  "html_template": "<!DOCTYPE html><html>...</html>",
  "variables_schema": {
    "name": {"type": "string", "required": false, "default": "Friend"},
    "promo_code": {"type": "string", "required": true},
    "bonus_amount": {"type": "number", "required": false}
  }
}
```

#### Response (201 Created)

```json
{
  "template_id": "promo_welcome",
  "version": 1,
  "created_at": "2025-12-14T18:30:00Z",
  "status": "active"
}
```

---

### 7. POST /api/v1/webhook (внутренний)

Webhook от Postal. **Вызывается Postal, не AMS.**

#### Request (от Postal)

```http
POST /api/v1/webhook HTTP/1.1
Host: send1.example.com
Content-Type: application/json
X-Postal-Signature: sha256=abc123...

{
  "event": "MessageDelivered",
  "timestamp": 1734198600,
  "payload": {
    "message_id": "postal_123",
    "status": "delivered",
    "details": {...}
  }
}
```

#### Response (200 OK)

```json
{
  "received": true
}
```

---

## Трекинг endpoints (Tracking Service)

### GET /track/o

Трекинг открытия письма.

#### Request

```
GET /track/o?eid=dXNlckBnbWFpbC5jb20=&cid=camp_12345&mid=msg_67890 HTTP/1.1
```

#### Параметры (query string)

| Параметр | Описание |
|----------|----------|
| `eid` | Email получателя (Base64) |
| `cid` | ID кампании |
| `mid` | ID сообщения |

#### Response

- **Status:** 200 OK
- **Content-Type:** image/png
- **Body:** 1x1 transparent PNG

#### Побочные эффекты

1. Логирование события в БД
2. Webhook в AMS (асинхронно)

---

### GET /track/c

Трекинг клика по ссылке.

#### Request

```
GET /track/c?url=aHR0cHM6Ly9jYXNpbm8uY29t&eid=dXNlckBnbWFpbC5jb20=&cid=camp_12345&mid=msg_67890 HTTP/1.1
```

#### Параметры (query string)

| Параметр | Описание |
|----------|----------|
| `url` | Оригинальный URL (Base64) |
| `eid` | Email получателя (Base64) |
| `cid` | ID кампании |
| `mid` | ID сообщения |

#### Response

- **Status:** 302 Found
- **Location:** декодированный оригинальный URL

#### Побочные эффекты

1. Логирование события в БД
2. Webhook в AMS (асинхронно)

---

## Rate Limiting

### Лимиты по умолчанию

| Endpoint | Лимит | Окно |
|----------|-------|------|
| `POST /send` | 100 req/sec | per API key |
| `POST /batch` | 10 req/sec | per API key |
| `GET /status` | 1000 req/min | per API key |
| `GET /health` | без лимита | — |
| `GET /track/*` | 10000 req/sec | global |

### Заголовки rate limit

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1734198660
```

---

## Callbacks в AMS (Webhooks)

Send Server отправляет webhooks обратно в AMS.

### Endpoint в AMS

Настраивается при установке:
```
AMS_CALLBACK_URL=https://ams.example.com/api/webhooks/send_server
```

### Формат callback

```http
POST /api/webhooks/send_server HTTP/1.1
Host: ams.example.com
Content-Type: application/json
X-Signature: sha256=abc123...
X-Server-ID: send1.example.com

{
  "event_type": "delivery",
  "timestamp": "2025-12-14T18:30:00Z",
  "data": {
    "message_id": "msg_67890",
    "campaign_id": "camp_12345",
    "recipient": "user@gmail.com",
    "status": "delivered",
    "details": {}
  }
}
```

### Типы событий

| Event Type | Когда отправляется |
|------------|-------------------|
| `queued` | Письмо принято в очередь |
| `sent` | Отправлено в Postal |
| `delivered` | Доставлено |
| `bounced` | Отклонено |
| `opened` | Открыто |
| `clicked` | Клик по ссылке |
| `complained` | Жалоба на спам |
| `failed` | Ошибка |

---

## Примеры кода

### Python (requests)

```python
import requests
import json

API_URL = "https://send1.example.com/api/v1"
API_KEY = "a1b2c3d4e5f6..."

def send_email(recipient, template_id, variables, tracking):
    response = requests.post(
        f"{API_URL}/send",
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json"
        },
        json={
            "recipient": recipient,
            "template_id": template_id,
            "from_name": "Kate",
            "from_email": "kate@domain.com",
            "subject": "Welcome!",
            "variables": variables,
            "tracking": tracking
        }
    )
    
    if response.status_code == 202:
        return response.json()
    else:
        raise Exception(f"Error: {response.json()}")
```

### Ruby

```ruby
require 'net/http'
require 'json'

API_URL = "https://send1.example.com/api/v1"
API_KEY = "a1b2c3d4e5f6..."

def send_email(recipient:, template_id:, variables:, tracking:)
  uri = URI("#{API_URL}/send")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{API_KEY}"
  request["Content-Type"] = "application/json"
  request.body = {
    recipient: recipient,
    template_id: template_id,
    from_name: "Kate",
    from_email: "kate@domain.com",
    subject: "Welcome!",
    variables: variables,
    tracking: tracking
  }.to_json
  
  response = http.request(request)
  JSON.parse(response.body)
end
```

### cURL

```bash
curl -X POST https://send1.example.com/api/v1/send \
  -H "Authorization: Bearer a1b2c3d4e5f6..." \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "user@gmail.com",
    "template_id": "promo_welcome",
    "from_name": "Kate",
    "from_email": "kate@domain.com",
    "subject": "Welcome!",
    "variables": {"name": "John"},
    "tracking": {"campaign_id": "camp_123", "message_id": "msg_456"}
  }'
```

