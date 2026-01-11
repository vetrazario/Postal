# 🚨 НЕМЕДЛЕННЫЕ ИСПРАВЛЕНИЯ
## Критические проблемы, которые нужно исправить ПРЯМО СЕЙЧАС

**Дата:** 2026-01-11
**Время на выполнение:** ~30 минут
**Статус:** ⚠️ КРИТИЧНО

---

## ⚡ ШАГ 1: ПРИМЕНИТЬ МИГРАЦИИ БД (5 минут)

**Проблема:** База данных НЕ синхронизирована! Отсутствуют 10 таблиц!

```bash
# Применить все миграции
docker compose exec api rails db:migrate

# Проверить статус
docker compose exec api rails db:migrate:status

# Должны увидеть все миграции со статусом "up"
```

**Что это исправит:**
- ✅ Webhook функционал заработает
- ✅ SMTP credentials заработают
- ✅ Bounce handling заработает
- ✅ AI аналитика заработает
- ✅ System config UI заработает
- ✅ Unsubscribe заработает

---

## 🔒 ШАГ 2: ОТКЛЮЧИТЬ DOCKER SOCKET (2 минуты)

**Проблема:** API контейнер имеет доступ к Docker daemon хоста!

**Файл:** `docker-compose.yml`

Найти и **УДАЛИТЬ** строки 187-188:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro  # ❌ УДАЛИТЬ
  - ./docker-compose.yml:/project/docker-compose.yml:ro
```

Оставить только:
```yaml
volumes:
  - ./docker-compose.yml:/project/docker-compose.yml:ro
```

---

## 🔐 ШАГ 3: ВКЛЮЧИТЬ WEBHOOK VERIFICATION (2 минуты)

**Проблема:** Проверка подписи webhook ОТКЛЮЧЕНА в production!

**Файл:** `docker-compose.yml`

Найти строку 178 и **УДАЛИТЬ** или **ЗАКОММЕНТИРОВАТЬ**:
```yaml
# SKIP_POSTAL_WEBHOOK_VERIFICATION: 'true'  # ❌ УДАЛИТЬ ЭТУ СТРОКУ
```

Или изменить на:
```yaml
SKIP_POSTAL_WEBHOOK_VERIFICATION: ${SKIP_POSTAL_WEBHOOK_VERIFICATION:-false}
```

---

## 🔄 ШАГ 4: ПЕРЕЗАПУСТИТЬ СЕРВИСЫ (5 минут)

```bash
# Остановить все сервисы
docker compose down

# Запустить заново
docker compose up -d

# Проверить статус
docker compose ps

# Проверить логи
docker compose logs -f api
```

**Что проверить:**
- ✅ Все сервисы в статусе "Up (healthy)"
- ✅ Нет ошибок в логах
- ✅ API отвечает: `curl http://localhost:3000/api/v1/health`

---

## 🛡️ ШАГ 5: ПРОВЕРИТЬ ENV ПЕРЕМЕННЫЕ (10 минут)

**Файл:** `.env`

Убедитесь, что следующие переменные **НЕ** содержат `CHANGE_ME`:

```bash
# Проверить .env файл
grep "CHANGE_ME" .env

# Если нашлись CHANGE_ME - это КРИТИЧНО!
```

**Минимально необходимые переменные:**
```bash
SECRET_KEY_BASE=<64 hex chars>
ENCRYPTION_PRIMARY_KEY=<hex string>
ENCRYPTION_DETERMINISTIC_KEY=<hex string>
ENCRYPTION_KEY_DERIVATION_SALT=<hex string>
POSTGRES_PASSWORD=<strong password>
POSTAL_SIGNING_KEY=<64 hex chars>
WEBHOOK_SECRET=<64 hex chars>
```

**Генерация секретов:**
```bash
# Сгенерировать все нужные секреты
echo "SECRET_KEY_BASE=$(openssl rand -hex 32)"
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)"
echo "MARIADB_PASSWORD=$(openssl rand -hex 16)"
echo "RABBITMQ_PASSWORD=$(openssl rand -hex 16)"
echo "POSTAL_SIGNING_KEY=$(openssl rand -hex 32)"
echo "WEBHOOK_SECRET=$(openssl rand -hex 32)"

# Encryption keys (требуется Rails)
docker compose exec api rails db:encryption:init
```

---

## ✅ ПРОВЕРКА РАБОТОСПОСОБНОСТИ

После выполнения всех шагов, проверьте:

```bash
# 1. Health check
curl http://localhost:3000/api/v1/health | jq

# Должны увидеть:
# {
#   "status": "ok",
#   "database": "ok",
#   "redis": "ok",
#   "postal": "ok"
# }

# 2. Проверить таблицы БД
docker compose exec api rails runner "puts ActiveRecord::Base.connection.tables.sort"

# Должны увидеть все 15 таблиц:
# ai_analyses
# ai_settings
# api_keys
# ar_internal_metadata
# bounced_emails
# campaign_stats
# delivery_errors
# email_logs
# email_templates
# mailing_rules
# schema_migrations
# smtp_credentials
# system_configs
# tracking_events
# unsubscribes
# webhook_endpoints
# webhook_logs

# 3. Проверить миграции
docker compose exec api rails db:migrate:status

# Все должны быть "up"
```

---

## 📊 ЧТО ДАЛЬШЕ?

После выполнения немедленных исправлений:

1. **Прочитайте полный отчет:** `FULL_ERROR_ANALYSIS_REPORT.md`
2. **Исправьте высокоприоритетные проблемы:**
   - Weak encryption в `smtp_controller.rb`
   - IP-based auth → API key auth
   - N+1 queries в analytics
   - SMTP relay authentication

3. **Настройте мониторинг:**
   - Sentry для ошибок
   - Логи в централизованное хранилище
   - Метрики производительности

4. **Увеличьте memory limits** (для production):
   ```yaml
   api:
     deploy:
       resources:
         limits:
           memory: 1G  # было 400M

   postgres:
     deploy:
       resources:
         limits:
           memory: 1G  # было 350M

   postal:
     deploy:
       resources:
         limits:
           memory: 2G  # было 512M
   ```

---

## 🚨 ЕСЛИ ЧТО-ТО ПОШЛО НЕ ТАК

### Миграции не применяются:

```bash
# Проверить логи
docker compose logs api

# Попробовать вручную
docker compose exec api rails db:migrate:status
docker compose exec api rails db:migrate RAILS_ENV=production

# Если ошибка про encryption keys:
docker compose exec api rails db:encryption:init
# Скопировать ключи в .env
```

### Сервисы не стартуют:

```bash
# Проверить логи каждого сервиса
docker compose logs postgres
docker compose logs redis
docker compose logs api
docker compose logs postal

# Проверить ресурсы
docker stats
```

### База данных недоступна:

```bash
# Проверить PostgreSQL
docker compose exec postgres psql -U email_sender -d email_sender -c "SELECT 1;"

# Пересоздать БД (ОСТОРОЖНО! Потеряете данные!)
docker compose down
docker volume rm postal_postgres_data
docker compose up -d
docker compose exec api rails db:create db:migrate
```

---

**Время выполнения:** ~30 минут
**Сложность:** Низкая
**Риск:** Минимальный (все изменения безопасны)

✅ После выполнения этих шагов система будет в рабочем состоянии!
