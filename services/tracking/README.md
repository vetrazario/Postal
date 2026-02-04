# Tracking Service

Сервис для отслеживания открытий и кликов по email рассылкам.

## Архитектура

```
Email --> Pixel/Link --> Tracking Service --> Database
                            |                     |
                            v                     v
                        Events (Open/Click)      Stats
```

## Основные компоненты

### App (Sinatra)
- `app.rb` - основное приложение Sinatra с маршрутами

### Handlers
- `lib/tracking_handler.rb` - обработка событий трекинга
- `lib/event_logger.rb` - логирование событий в базу данных
- `lib/webhook_sender.rb` - отправка вебхуков в внешние системы

## API Endpoints

### Public (без аутентификации)
- `GET /track/o` - открытие письма (возвращает 1x1 пиксел)
- `GET /track/c` - клик по ссылке (redirect на целевой URL)
- `GET /unsubscribe` - страница отписки (GET)
- `POST /unsubscribe` - отписка от рассылки (POST, RFC 8058)

### Health
- `GET /health` - health check сервиса

## Параметры запросов

### Открытие письма (`/track/o`)
- `eid` - email recipient, закодированный в Base64 URL-safe
- `cid` - campaign ID, закодированный в Base64 URL-safe
- `mid` - message ID, закодированный в Base64 URL-safe

### Клик по ссылке (`/track/c`)
- `url` - целевой URL, закодированный в Base64 URL-safe
- `eid` - email recipient, закодированный в Base64 URL-safe
- `cid` - campaign ID, закодированный в Base64 URL-safe
- `mid` - message ID, закодированный в Base64 URL-safe

### Отписка (`/unsubscribe`)
- `eid` - email recipient, закодированный в Base64 URL-safe
- `cid` - campaign ID, закодированный в Base64 URL-safe (опционально)

## Логика работы

### Открытие письма
1. Пользователь открывает письмо в email клиенте
2. Email клиент загружает трекинг-пиксел: `<img src="https://domain/track/o?eid=...&cid=...&mid=...">`
3. Tracking Service получает запрос
4. Проверяется валидность параметров
5. Создается запись `EmailOpen` (если первое открытие)
6. Обновляется статистика кампании `CampaignStats`
7. Возвращается 1x1 прозрачный PNG пиксел

### Клик по ссылке
1. Пользователь кликает по ссылке в письме
2. Ссылка имеет формат: `https://domain/track/c?url=...&eid=...&cid=...&mid=...`
3. Tracking Service получает запрос
4. Проверяется валидность URL и параметров
5. Создается запись `EmailClick` (если первый клик)
6. Обновляется статистика кампании `CampaignStats`
7. Redirect (302) на целевой URL

### Защита от ботов
- Определение ботов по User-Agent
- Боты могут кликать, но не считаются в статистике
- Bot detection patterns:
  - `bot`, `crawl`, `spider`
  - `googlebot`, `yandexbot`, `bingbot`
  - `facebookexternalhit`, `twitterbot`
  - `whatsapp`, `mediapartners`

### Защита от перебора
- Проверка формата закодированных параметров (Base64 URL-safe)
- Валидация целевого URL (только http/https)
- Защита от open redirect (атак через `javascript:` и `data:` схем)

## Требования

- Ruby 2.7+
- Sinatra 2.0+
- PostgreSQL 15+
- Redis 7.0+

## Конфигурация

Переменные окружения:

```
DATABASE_URL          # URL для подключения к PostgreSQL
REDIS_URL             # URL для подключения к Redis
LOG_LEVEL             # Уровень логирования (debug/info/warn/error/fatal)
```

## Тестирование

```bash
# Health check
curl http://localhost/health

# Открытие письма (замените параметры)
curl "http://localhost/track/o?eid=$(echo -n 'test@example.com' | base64)&cid=$(echo -n 'test_campaign' | base64)"

# Клик по ссылке (замените URL и параметры)
curl -I "http://localhost/track/c?url=$(echo -n 'https://example.com' | base64)&eid=$(echo -n 'test@example.com' | base64)"

# Отписка
curl "http://localhost/unsubscribe?eid=$(echo -n 'test@example.com' | base64)"
```

## Метрики

Отслеживаемые события:
- `open` - открытие письма (через пиксел)
- `click` - клик по ссылке
- `unsubscribe` - отписка от рассылки

Статистика по кампаниям:
- Количество отправленных писем
- Количество доставленных писем
- Количество bounced писем
- Количество открытий
- Количество кликов

## Кэширование

- PNG пиксел кэшируется на 1 год (immutable)
- Redirect на URL использует статус 301 (Permanent)
- Заголовки кэширования:
  ```
  Cache-Control: public, max-age=31536000, immutable
  Expires: [дата через год]
  ETag: [MD5 хеш пиксела]
  ```
