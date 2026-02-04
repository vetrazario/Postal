# API Service

REST API сервис для управления отправкой email, отслеживанием и интеграцией с AMS Enterprise.

## Архитектура

```
Client --> Controllers --> Services --> Models --> Database
              |              |           |
              v              v           v
            Jobs <-----------+-----------+
```

## Основные компоненты

### Controllers
- `ApplicationController` - базовый контроллер с аутентификацией и обработкой ошибок
- `Api::V1::` - API контроллеры версии 1
- `Dashboard::` - веб-интерфейс администратора
- `TrackingController` - публичные endpoint'ы для трекинга (клики, открытия)

### Services
- `EmailSendingService` - основная логика отправки email
- `PostalClient` - клиент для взаимодействия с Postal mail server
- `EmailValidator` - валидация email адресов
- `EmailBlocker` - проверка блокировок (unsubscribe/bounce)
- `ErrorClassifier` - классификация ошибок доставки
- `TrackingInjector` - внедрение трекинга в HTML
- `EmailMasker` - безопасное маскирование email адресов

### Models
- `EmailLog` - журнал всех отправленных писем
- `ApiKey` - API ключи для аутентификации
- `EmailTemplate` - шаблоны писем
- `CampaignStats` - статистика по кампаниям
- `TrackingEvent` - события трекинга (открытия, клики)
- `EmailOpen` - записи об открытиях
- `EmailClick` - записи о кликах
- `DeliveryError` - ошибки доставки
- `BouncedEmail` - bounced email адреса
- `Unsubscribe` - отписки от рассылки
- `SystemConfig` - конфигурация системы

### Jobs
- `BuildEmailJob` - рендеринг HTML и внедрение трекинга
- `SendToPostalJob` - отправка письма через Postal
- `SendSmtpEmailJob` - обработка email от SMTP Relay
- `ReportToAmsJob` - отправка статусов в AMS

## API Endpoints

### Public (без аутентификации)
- `GET /api/v1/health` - health check
- `GET /go/:slug` - клик по ссылке (redirect)
- `GET /t/c/:token` - клик по токену
- `GET /t/o/:token` - открытие письма (pixel)
- `POST /unsubscribe` - отписка от рассылки

### Authenticated (требуется API ключ)
- `POST /api/v1/send` - отправить одно письмо
- `POST /api/v1/batch` - отправить batch писем
- `GET /api/v1/status/:message_id` - статус письма
- `GET /api/v1/stats` - статистика
- `POST /api/v1/templates` - создать шаблон
- `POST /api/v1/webhook` - вебхук от Postal (с верификацией подписи)

### Internal (только для внутренних сервисов)
- `GET /api/v1/internal/smtp_relay_config` - конфигурация SMTP Relay
- `POST /api/v1/internal/smtp_auth` - аутентификация SMTP Relay
- `POST /api/v1/internal/tracking_event` - событие трекинга

### Dashboard (Basic Auth)
- `GET /dashboard/` - главная страница со статистикой
- `GET/POST /dashboard/api_keys` - управление API ключами
- `GET/POST /dashboard/templates` - управление шаблонами
- `GET/POST /dashboard/logs` - логи писем
- `GET/POST /dashboard/analytics` - аналитика
- `GET/POST /dashboard/settings` - настройки системы
- `GET/POST /dashboard/smtp_credentials` - SMTP credentials

## Требования

- Ruby 3.1+
- Rails 7.1+
- PostgreSQL 15+
- Redis 7.0+

## Конфигурация

Основные переменные окружения:

```
DATABASE_URL          # URL для подключения к PostgreSQL
REDIS_URL             # URL для подключения к Redis
ALLOWED_SENDER_DOMAINS   # Разрешенные домены отправителей (через запятую)
POSTAL_API_URL       # URL Postal API
POSTAL_API_KEY       # API ключ Postal
AMS_CALLBACK_URL      # URL для вебхуков в AMS
API_KEY_SALT         # Соль для хеширования API ключей
LOG_LEVEL             # Уровень логирования (debug/info/warn/error/fatal)
```

## Развитие

1. Добавить новый контроллер в `app/controllers/api/v1/`
2. Создать сервис в `app/services/`
3. Добавить маршрут в `config/routes.rb`
4. Создать миграцию базы данных в `db/migrate/`
5. Добавить тесты в `spec/`

## Тестирование

```bash
# Запуск тестов
cd services/api
bundle exec rspec

# Health check
curl http://localhost/api/v1/health

# Отправка тестового письма
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"recipient": "test@example.com", "from_email": "sender@example.com", "subject": "Test"}'
```
