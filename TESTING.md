# Инструкция по тестированию

## Быстрый запуск тестов

### Через Docker Compose (рекомендуется)

```bash
# 1. Убедитесь, что все сервисы запущены
docker compose up -d postgres redis

# 2. Запустите тесты в контейнере API
docker compose exec api bundle exec rspec

# 3. Запустите RuboCop
docker compose exec api bundle exec rubocop

# 4. Запустите Brakeman
docker compose exec api bundle exec brakeman --no-pager
```

### Полный набор проверок

```bash
# Запуск всех проверок одной командой
docker compose exec api bash test_runner.sh
```

## Отдельные тесты

### RSpec тесты

```bash
# Все тесты
docker compose exec api bundle exec rspec

# Конкретный файл
docker compose exec api bundle exec rspec spec/requests/webhooks_spec.rb

# Конкретный тест
docker compose exec api bundle exec rspec spec/requests/webhooks_spec.rb:36

# С подробным выводом
docker compose exec api bundle exec rspec --format documentation
```

### RuboCop (проверка стиля)

```bash
# Проверка всех файлов
docker compose exec api bundle exec rubocop

# Автоисправление
docker compose exec api bundle exec rubocop -a

# Проверка конкретного файла
docker compose exec api bundle exec rubocop app/controllers/api/v1/webhooks_controller.rb
```

### Brakeman (проверка безопасности)

```bash
# Базовая проверка
docker compose exec api bundle exec brakeman --no-pager

# С выводом в файл
docker compose exec api bundle exec brakeman -o brakeman-report.html
```

## Локальный запуск (без Docker)

Если у вас установлен Ruby и Bundler локально:

```bash
cd services/api

# Установка зависимостей
bundle install

# Настройка тестовой базы данных
RAILS_ENV=test bundle exec rails db:create db:migrate

# Запуск тестов
bundle exec rspec
```

## Переменные окружения для тестов

Тесты автоматически используют следующие переменные (если не заданы):

- `RAILS_ENV=test`
- `DATABASE_URL=postgres://email_sender:test_password@localhost:5432/email_sender_test`
- `REDIS_URL=redis://localhost:6379/0`
- `SECRET_KEY_BASE=test_secret_key_base_for_ci_...`
- `ENCRYPTION_PRIMARY_KEY=test_encryption_primary_key_32_chars`
- `ENCRYPTION_DETERMINISTIC_KEY=test_encryption_deterministic_key_32_chars`
- `ENCRYPTION_KEY_DERIVATION_SALT=test_encryption_salt_32_chars`
- `DASHBOARD_USERNAME=test_admin`
- `DASHBOARD_PASSWORD=test_password`
- `POSTAL_SIGNING_KEY=test_postal_signing_key_64_hex_chars_...`
- `POSTAL_WEBHOOK_PUBLIC_KEY=test_public_key`
- `CORS_ORIGINS=http://localhost:3000`
- `ALLOWED_SENDER_DOMAINS=example.com`
- `LOG_LEVEL=info`

## Структура тестов

```
services/api/spec/
├── requests/           # Request specs (интеграционные тесты)
│   ├── webhooks_spec.rb
│   ├── dashboard_spec.rb
│   ├── rate_limiting_spec.rb
│   ├── emails_spec.rb
│   ├── batches_spec.rb
│   └── health_spec.rb
├── models/             # Model specs
│   ├── email_log_spec.rb
│   └── api_key_spec.rb
├── jobs/               # Job specs
│   └── send_to_postal_job_spec.rb
├── services/           # Service specs
│   └── message_id_generator_spec.rb
└── factories/          # FactoryBot factories
    ├── email_logs.rb
    └── api_keys.rb
```

## Покрытие кода

Для просмотра покрытия кода используйте SimpleCov:

```bash
# В spec/spec_helper.rb уже настроен SimpleCov
docker compose exec api bundle exec rspec

# Результаты будут в coverage/index.html
# Откройте файл в браузере
```

## CI/CD

Тесты автоматически запускаются в GitHub Actions при каждом push (см. `.github/workflows/ci.yml`).

