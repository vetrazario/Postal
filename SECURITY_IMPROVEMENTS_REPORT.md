# Отчёт о выполненных улучшениях безопасности

## 1. Изменённые файлы

### ФАЗА 0 — Инвентаризация и базовые исправления
- `services/api/app/controllers/api/v1/webhooks_controller.rb` — добавлена проверка подписи
- `services/api/app/controllers/dashboard_controller.rb` — убраны дефолтные значения Basic Auth
- `services/api/config/application.rb` — исправлен CORS (заменён `*` на список доменов)
- `services/api/config/initializers/rack_attack.rb` — реализован rate limiting
- `services/api/config/routes.rb` — добавлена аутентификация для Sidekiq Web UI
- `services/api/config/environments/production.rb` — включён принудительный SSL
- `services/api/config/initializers/required_env.rb` — создан (валидация переменных окружения)
- `services/api/config/initializers/cors.rb` — удалён (дублировал настройки)
- `services/api/docker-entrypoint.sh` — создан (автоматические миграции)
- `services/api/Dockerfile` — обновлён (добавлен entrypoint)
- `services/api/db-init.sh` — исправлен (использует RAILS_ENV из окружения)
- `.gitignore` — обновлён (улучшена защита .env файлов)
- `services/api/.gitignore` — обновлён (добавлены правила для .env)
- `env.example.txt` — обновлён (добавлены новые переменные)

### ФАЗА 1 — Webhooks
- `services/api/app/lib/encrypto_signo.rb` — создан (модуль для проверки подписи)
- `services/api/app/controllers/api/v1/webhooks_controller.rb` — реализована проверка подписи через публичный ключ
- `services/api/spec/requests/webhooks_spec.rb` — создан (тесты для webhooks)

### ФАЗА 2 — Доступы
- `services/api/app/controllers/dashboard_controller.rb` — убраны fallback значения
- `services/api/config/routes.rb` — добавлена аутентификация для Sidekiq, условное монтирование
- `services/api/spec/requests/dashboard_spec.rb` — создан (тесты для Dashboard)

### ФАЗА 3 — Rate limiting и CORS
- `services/api/config/initializers/rack_attack.rb` — полностью реализован
- `services/api/config/application.rb` — исправлен CORS (использует CORS_ORIGINS)
- `services/api/spec/requests/rate_limiting_spec.rb` — создан (тесты для rate limiting)
- `docs/DEPLOYMENT.md` — обновлён (добавлена документация CORS_ORIGINS)

### ФАЗА 4 — Секреты и .env
- `.gitignore` — обновлён (правила для .env)
- `services/api/.gitignore` — обновлён (правила для .env)
- `env.example.txt` — обновлён (все необходимые переменные)

### ФАЗА 5 — Docker
- `docker-compose.yml` — обновлён (добавлены переменные, комментарии)
- `services/api/docker-entrypoint.sh` — создан
- `services/api/Dockerfile` — обновлён
- `docs/DEPLOYMENT.md` — обновлён (добавлены команды запуска)

### ФАЗА 6 — CI
- `.github/workflows/ci.yml` — создан
- `services/api/.rubocop.yml` — создан
- `services/api/Gemfile` — добавлен brakeman

---

## 2. Новые ENV переменные

### Добавленные переменные:

1. **POSTAL_WEBHOOK_PUBLIC_KEY**
   - Описание: Публичный ключ для проверки подписи webhook от Postal (PEM формат)
   - Документация: `env.example.txt` (строки 73-79), `docs/DEPLOYMENT.md`
   - Обязательная: Да (валидируется в `required_env.rb`)

2. **DASHBOARD_USERNAME**
   - Описание: Учетные данные для Dashboard (обязательно)
   - Документация: `env.example.txt` (строки 139-141), `docs/DEPLOYMENT.md`
   - Обязательная: Да (валидируется в `required_env.rb`)

3. **DASHBOARD_PASSWORD**
   - Описание: Пароль для Dashboard (обязательно)
   - Документация: `env.example.txt` (строки 139-141), `docs/DEPLOYMENT.md`
   - Обязательная: Да (валидируется в `required_env.rb`)

4. **SIDEKIQ_WEB_USERNAME**
   - Описание: Учетные данные для Sidekiq Web UI (опционально)
   - Документация: `env.example.txt` (строки 143-145), `docs/DEPLOYMENT.md`
   - Обязательная: Нет (если не заданы, Sidekiq Web не монтируется)

5. **SIDEKIQ_WEB_PASSWORD**
   - Описание: Пароль для Sidekiq Web UI (опционально)
   - Документация: `env.example.txt` (строки 143-145), `docs/DEPLOYMENT.md`
   - Обязательная: Нет (если не заданы, Sidekiq Web не монтируется)

6. **CORS_ORIGINS**
   - Описание: Разрешенные домены для CORS (через запятую)
   - Документация: `env.example.txt` (строки 151-155), `docs/DEPLOYMENT.md` (строки 253-285)
   - Обязательная: В production — да, в development/test — нет (по умолчанию `*`)

### Где задокументировано:
- **env.example.txt** — основной файл с примерами всех переменных
- **docs/DEPLOYMENT.md** — раздел "Создание .env файла" и "Команды запуска"
- **services/api/config/initializers/required_env.rb** — валидация обязательных переменных

---

## 3. Как проверить локально

### Подготовка:
```bash
# 1. Создать .env из примера
cp env.example.txt .env

# 2. Отредактировать .env и заполнить все значения
# Минимальные значения для local dev:
#   DOMAIN=localhost
#   RAILS_ENV=development
#   POSTGRES_PASSWORD=test_password_123
#   MARIADB_PASSWORD=test_password_123
#   RABBITMQ_PASSWORD=test_password_123
#   SECRET_KEY_BASE=$(openssl rand -hex 32)
#   ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 16)
#   ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 16)
#   ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 16)
#   DASHBOARD_USERNAME=admin
#   DASHBOARD_PASSWORD=admin
#   SIDEKIQ_WEB_USERNAME=admin
#   SIDEKIQ_WEB_PASSWORD=admin
#   POSTAL_WEBHOOK_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
#   CORS_ORIGINS=*  # или оставить пустым для dev
```

### Запуск:
```bash
# 3. Запустить все сервисы
docker compose up -d

# 4. Проверить статус
docker compose ps

# 5. Проверить логи миграций
docker compose logs api | grep -i migration
docker compose logs sidekiq | grep -i migration

# 6. Проверить health
curl http://localhost/api/v1/health

# 7. Проверить Dashboard (требует Basic Auth)
curl -u admin:admin http://localhost/dashboard

# 8. Проверить Sidekiq Web UI (требует Basic Auth)
curl -u admin:admin http://localhost/sidekiq

# 9. Создать API ключ
docker compose exec api rails runner "key = ApiKey.generate(name: 'Test'); puts 'API Key: ' + key[1]"

# 10. Проверить rate limiting
# Отправить 101 запрос подряд - должен вернуть 429
for i in {1..101}; do
  curl -H "Authorization: Bearer YOUR_API_KEY" http://localhost/api/v1/send
done
```

### Тестирование:
```bash
# Запустить тесты
docker compose exec api bundle exec rspec

# Запустить RuboCop
docker compose exec api bundle exec rubocop

# Запустить Brakeman
docker compose exec api bundle exec brakeman
```

---

## 4. Оставшиеся риски

### Низкий приоритет:
1. **CSRF защита для Dashboard** — сейчас отключена (`skip_before_action :verify_authenticity_token`). Рекомендуется включить для production.
2. **Отсутствие тестов для tracking сервиса** — нет spec файлов в `services/tracking/spec/`. Рекомендуется добавить базовые тесты.
3. **Throttle для неуспешных попыток аутентификации** — работает на все запросы с Authorization header, а не только на неуспешные (ограничение Rack::Attack, который работает до контроллера). Это защищает от брутфорса, но не идеально точно.
4. **Отсутствие мониторинга** — нет интеграции с системами мониторинга (кроме опционального Sentry). Рекомендуется добавить Prometheus/Grafana.

### Средний приоритет:
5. **Валидация формата POSTAL_WEBHOOK_PUBLIC_KEY** — нет проверки, что ключ валидный PEM. Приложение упадёт при старте, если ключ невалидный, но лучше валидировать заранее.
6. **Ротация секретов** — нет механизма ротации API ключей и других секретов без простоя.

---

## Итог

Все основные задачи выполнены:
- ✅ Webhooks защищены проверкой подписи
- ✅ Dashboard и Sidekiq Web UI защищены аутентификацией
- ✅ CORS настроен безопасно
- ✅ Rate limiting реализован
- ✅ .env файлы защищены от коммита
- ✅ Миграции выполняются автоматически
- ✅ CI настроен

Проект готов к использованию с улучшенной безопасностью.

