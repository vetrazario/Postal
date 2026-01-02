# Глубокий анализ проекта Postal: Проблемы и план исправления

## Дата анализа: 2026-01-02

---

## КРИТИЧЕСКИЕ ПРОБЛЕМЫ (Приоритет 1 - Исправить немедленно)

### 1. ПАРОЛИ В ОТКРЫТОМ ВИДЕ В postal.yml

**Файл:** `config/postal.yml`

**Проблема:** Пароли к базам данных хранятся в открытом виде в конфигурационном файле:
```yaml
main_db:
  password: 3d13ad32d93c33da6e3c9cc09e3525bca7f51c1a3a5fc908b6bcad451cf4567c  # КРИТИЧНО!

message_db:
  password: 3d13ad32d93c33da6e3c9cc09e3525bca7f51c1a3a5fc908b6bcad451cf4567c  # КРИТИЧНО!

rabbitmq:
  password: 81b076b7a0216de1633a5dfbb7c41689  # КРИТИЧНО!

rails:
  secret_key: 45fa5bf127ca8a633b091761a6f7ac5b8a13b783c02deb2b4246a31c3c67989f  # КРИТИЧНО!
```

**Риск:** Компрометация всех баз данных и сессий при утечке файла

**Решение:**
1. Использовать `postal.yml.template` с переменными окружения
2. Генерировать `postal.yml` динамически при запуске контейнера
3. Добавить `config/postal.yml` в `.gitignore`
4. Ротировать все скомпрометированные пароли

---

### 2. SMTP RELAY БЕЗ АУТЕНТИФИКАЦИИ

**Файл:** `services/smtp-relay/server.js`

**Проблема:** SMTP сервер принимает соединения от любого клиента без проверки:
```javascript
// Handle authentication (optional)
onAuth(auth, session, callback) {
  console.log(`[${session.id}] Auth attempt: ${auth.username}`);
  // For now, accept all auth attempts  <-- КРИТИЧНО!
  return callback(null, { user: auth.username });
}

authOptional: true,  // Аутентификация не обязательна!
```

**Риск:** Любой может использовать сервер как open relay для спама

**Решение:**
1. Сделать аутентификацию обязательной (`authOptional: false`)
2. Проверять учетные данные через API или базу данных
3. Добавить IP whitelist или rate limiting
4. Логировать все попытки аутентификации

---

### 3. ENDPOINT /api/v1/smtp/receive ПОЛНОСТЬЮ ОТКРЫТ (ПОДТВЕРЖДЕНО!)

**Файл:** `services/api/app/controllers/api/v1/smtp_controller.rb`

**Проблема:** Endpoint ЯВНО отключает аутентификацию:
```ruby
class SmtpController < ApplicationController
  # Skip API key authentication for internal SMTP relay
  skip_before_action :authenticate_api_key  # КРИТИЧНО! ПОЛНОСТЬЮ ОТКРЫТ!

  def receive
    # Любой может отправить сюда данные и инжектить письма!
    EmailLog.create!(...)  # Создаётся запись в БД
    SendSmtpEmailJob.perform_later(...)  # Письмо отправляется!
  end
end
```

**Риск:** КРИТИЧЕСКИЙ! Любой может:
- Инжектить произвольные письма в систему
- Использовать сервер для спама
- Заполнить базу данных
- Исчерпать ресурсы

**Решение:**
1. Добавить API ключ для SMTP relay (SMTP_RELAY_API_KEY)
2. Проверять IP адрес (только из Docker network)
3. Добавить rate limiting специально для этого endpoint
4. Использовать HMAC подпись для верификации запросов

---

### 4. OPEN REDIRECT УЯЗВИМОСТЬ В TRACKING

**Файл:** `services/tracking/lib/tracking_handler.rb`

**Проблема:** URL из параметра декодируется и редиректит без валидации:
```ruby
def handle_click(url:, eid:, cid:, mid:, ip:, user_agent:)
  original_url = Base64.urlsafe_decode64(url) rescue nil
  # ...
  { success: true, url: original_url }  # Редирект на любой URL!
end
```

**Риск:** Злоумышленник может создать tracking ссылку с редиректом на фишинговый сайт

**Решение:**
1. Валидировать URL перед редиректом
2. Проверять домен против whitelist
3. Добавить промежуточную страницу с предупреждением
4. Логировать подозрительные редиректы

---

### 5. ОТСУТСТВУЕТ ФАЙЛ htpasswd (ПОДТВЕРЖДЕНО!)

**Файл:** `config/nginx.conf` (строка 158)

**Проверка:**
```bash
$ ls -la /home/user/Postal/config/htpasswd
htpasswd file NOT FOUND
```

**Проблема:** Nginx ожидает файл `/etc/nginx/.htpasswd`, но его нет:
```nginx
location /postal/ {
    auth_basic "Postal Administration";
    auth_basic_user_file /etc/nginx/.htpasswd;  # Файл не существует!
```

**Риск:** Nginx вернёт 500 ошибку при попытке доступа к /postal/

**Решение:**
1. Создать файл `config/htpasswd`:
   ```bash
   htpasswd -bc config/htpasswd admin $DASHBOARD_PASSWORD
   ```
2. Добавить в docker-compose volume mapping
3. Добавить в процесс установки (install.sh)

---

## ВЫСОКИЙ ПРИОРИТЕТ (Приоритет 2 - Исправить в ближайшее время)

### 6. RATE LIMITING ТОЛЬКО ПО IP

**Файл:** `services/api/config/initializers/rack_attack.rb`

**Проблема:** Rate limiting только по IP, но не по API ключу:
```ruby
throttle('api/send', limit: 100, period: 1.minute) do |req|
  req.ip if req.post? && req.path.in?(['/api/v1/send', '/api/v1/batch'])
end
```

**Риск:**
- Один API ключ может исчерпать лимит для всех клиентов за NAT
- Скомпрометированный API ключ может спамить без ограничений

**Решение:**
```ruby
throttle('api/send/by_key', limit: 1000, period: 1.minute) do |req|
  next unless req.post? && req.path.in?(['/api/v1/send', '/api/v1/batch'])

  token = req.env['HTTP_AUTHORIZATION']&.split(' ')&.last
  Digest::SHA256.hexdigest(token) if token.present?
end
```

---

### 7. ОТСУТСТВУЕТ CSP HEADER

**Файл:** `config/nginx.conf`

**Проблема:** Нет Content-Security-Policy header:
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
# Нет CSP!
```

**Риск:** XSS атаки на Dashboard

**Решение:**
```nginx
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always;
```

---

### 8. ДУБЛИРОВАНИЕ WEBHOOK ЛОГИКИ

**Файлы:**
- `services/tracking/lib/tracking_handler.rb`
- `services/api/app/services/webhook_sender.rb`

**Проблема:** Tracking service пытается отправлять webhook напрямую, но код не работает:
```ruby
def enqueue_webhook_job(message_id, event_type, data)
  # Use Sidekiq to enqueue job
  require 'sidekiq'
  # ...
  # This will be handled by ReportToAmsJob in the API service
  # For now, we'll just log it  <-- НИКОГДА НЕ ОТПРАВЛЯЕТСЯ!
  puts "Webhook: #{event_type} for #{message_id}"
end
```

**Риск:** Tracking события никогда не отправляются в AMS

**Решение:**
1. Использовать HTTP запрос к API вместо Sidekiq
2. Или настроить правильный Sidekiq client
3. Или объединить сервисы

---

### 9. SSL СЕРТИФИКАТЫ - РАЗНЫЕ ПУТИ

**Файл:** `config/nginx.conf`

**Проблема:** Разные пути для сертификатов:
```nginx
# Основной сервер
ssl_certificate /etc/letsencrypt/live/linenarrow.com/fullchain.pem;

# Postal subdomain
ssl_certificate /etc/letsencrypt/live/postal.linenarrow.com/fullchain.pem;  # Может не существовать!
```

**Риск:** Nginx не запустится если сертификат не найден

**Решение:**
1. Использовать wildcard сертификат `*.linenarrow.com`
2. Или генерировать сертификаты для обоих доменов
3. Добавить fallback конфигурацию

---

### 10. ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ - НЕПОЛНАЯ ВАЛИДАЦИЯ (ПРОВЕРЕНО)

**Файл:** `services/api/config/initializers/required_env.rb`

**Текущее состояние:** Валидация существует, но НЕ проверяет все критические переменные:
```ruby
REQUIRED_ENV = {
  'SECRET_KEY_BASE' => 'Rails secret key base',
  'DATABASE_URL' => 'Database connection URL',
  'REDIS_URL' => 'Redis connection URL',
  'ENCRYPTION_PRIMARY_KEY' => 'Encryption primary key',
  'ENCRYPTION_DETERMINISTIC_KEY' => 'Encryption deterministic key',
  'ENCRYPTION_KEY_DERIVATION_SALT' => 'Encryption key derivation salt',
  'POSTAL_SIGNING_KEY' => 'Postal signing key'
  # НЕ ПРОВЕРЯЮТСЯ:
  # - POSTAL_API_KEY (критично для отправки!)
  # - WEBHOOK_SECRET (критично для безопасности!)
  # - DASHBOARD_USERNAME/PASSWORD (опционально помечено)
}.freeze
```

**Проблема:** Сервис может запуститься без POSTAL_API_KEY и упасть при первой отправке

**Решение:** Добавить недостающие переменные:
```ruby
REQUIRED_ENV = {
  # ... существующие ...
  'POSTAL_API_KEY' => 'Postal API key for sending emails',
  'WEBHOOK_SECRET' => 'Webhook signing secret'
}.freeze
```

---

## СРЕДНИЙ ПРИОРИТЕТ (Приоритет 3 - Исправить планово)

### 11. ЛОГИРОВАНИЕ ЧУВСТВИТЕЛЬНЫХ ДАННЫХ

**Файл:** `services/api/app/services/postal_client.rb`

**Проблема:** Возможное логирование API ключей:
```ruby
response = HTTParty.post(
  "#{@api_url}/api/v1/send/message",
  headers: {
    'X-Server-API-Key' => @api_key,  # Может логироваться!
  },
  debug_output: Rails.logger,  # ЛОГИРУЕТ ВСЁ!
```

**Риск:** API ключи могут попасть в лог-файлы

**Решение:**
1. Убрать `debug_output` в production
2. Фильтровать чувствительные заголовки
3. Использовать Rails logger filters

---

### 12. HARDCODED ДОМЕН В NGINX

**Файл:** `config/nginx.conf`

**Проблема:** Домен linenarrow.com захардкожен в нескольких местах:
```nginx
ssl_certificate /etc/letsencrypt/live/linenarrow.com/fullchain.pem;
server_name postal.linenarrow.com;
```

**Решение:**
1. Использовать шаблонизацию nginx.conf
2. Или использовать envsubst при запуске
3. Генерировать конфиг из template

---

### 13. НЕТ GRACEFUL SHUTDOWN ДЛЯ ВСЕХ СЕРВИСОВ

**Проблема:** Только SMTP relay имеет правильную обработку SIGTERM

**Решение:**
1. Добавить graceful shutdown для API (Puma уже поддерживает)
2. Настроить Sidekiq timeout
3. Добавить pre-stop hooks в docker-compose

---

### 14. ОТСУТСТВУЕТ BACKUP СТРАТЕГИЯ

**Проблема:** Нет автоматического backup для:
- PostgreSQL
- MariaDB
- Redis (AOF включен, но не хватает)

**Решение:**
1. Добавить cron-контейнер для backup
2. Настроить pg_dump и mysqldump
3. Sync на внешнее хранилище (S3, etc.)

---

### 15. MEMORY LIMITS МОГУТ БЫТЬ НЕДОСТАТОЧНЫ

**Файл:** `docker-compose.yml`

**Проблема:** Низкие лимиты памяти для некоторых сервисов:
```yaml
postgres:
  memory: 350M  # Возможно мало для production

rabbitmq:
  memory: 200M  # Может не хватить при нагрузке
```

**Риск:** OOM killer может убить сервисы

**Решение:**
1. Провести нагрузочное тестирование
2. Увеличить лимиты или убрать их
3. Настроить мониторинг памяти

---

## НИЗКИЙ ПРИОРИТЕТ (Приоритет 4 - Улучшения)

### 16. НЕТ HEALTH CHECK ДЛЯ CERTBOT

**Файл:** `docker-compose.yml`

```yaml
certbot:
  # Нет healthcheck!
  entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
```

---

### 17. НЕТ ВЕРСИОНИРОВАНИЯ ОБРАЗОВ

**Файл:** `docker-compose.yml`

```yaml
postal:
  image: ghcr.io/postalserver/postal:latest  # Не reproducible!
```

**Решение:** Использовать конкретные версии образов

---

### 18. ОТСУТСТВУЕТ MONITORING

**Проблема:** Нет Prometheus/Grafana для мониторинга

**Решение:**
1. Добавить Prometheus для сбора метрик
2. Экспортировать метрики из Rails/Sidekiq
3. Настроить алерты

---

## ПЛАН ИСПРАВЛЕНИЯ

### Фаза 1: Критические исправления (1-2 дня) ✅ ВЫПОЛНЕНО

1. ✅ **[P1-1]** Исправить postal.yml - использовать переменные окружения
2. ✅ **[P1-2]** Защитить SMTP relay аутентификацией
3. ✅ **[P1-3]** Проверить и защитить /api/v1/smtp/receive
4. ✅ **[P1-4]** Исправить Open Redirect в tracking
5. ✅ **[P1-5]** Создать htpasswd файл

### Фаза 2: Высокий приоритет (3-5 дней) ✅ ВЫПОЛНЕНО (частично)

6. ✅ **[P2-6]** Добавить rate limiting по API ключу
7. ✅ **[P2-7]** Добавить CSP header
8. ✅ **[P2-8]** Исправить webhook в tracking service
9. ⏳ **[P2-9]** Унифицировать SSL сертификаты
10. ✅ **[P2-10]** Добавить валидацию env переменных

### Фаза 3: Средний приоритет (1-2 недели)

11. ✅ **[P3-11]** Убрать логирование чувствительных данных
12. ⏳ **[P3-12]** Шаблонизировать nginx.conf
13. ⏳ **[P3-13]** Добавить graceful shutdown
14. ⏳ **[P3-14]** Настроить backup
15. ⏳ **[P3-15]** Оптимизировать memory limits

### Фаза 4: Улучшения (по возможности)

16. ⏳ **[P4-16]** Health check для certbot
17. ⏳ **[P4-17]** Версионирование образов
18. ⏳ **[P4-18]** Добавить monitoring

### ДОПОЛНИТЕЛЬНО: E2E Тестирование ✅ ДОБАВЛЕНО

- ✅ Создана система E2E тестирования (bash + Python/pytest)
- ✅ Добавлены команды в Makefile (test-e2e, test-security, validate)
- ✅ Добавлен docker-compose.test.yml для контейнеризованного тестирования

---

## КОМАНДЫ ДЛЯ ПРОВЕРКИ

```bash
# Проверить открытые порты
netstat -tlnp

# Проверить healthcheck всех контейнеров
docker compose ps

# Проверить логи на ошибки
docker compose logs --tail=100 | grep -i error

# Тест SMTP relay без аутентификации
swaks --to test@example.com --from test@example.com --server localhost:2587

# Проверить Open Redirect
curl -I "https://linenarrow.com/track/c?url=$(echo -n 'https://evil.com' | base64)&eid=dGVzdA&cid=dGVzdA&mid=dGVzdA"
```

---

## ГДЕ ЗАДАЮТСЯ НОВЫЕ ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ

### Обзор потока конфигурации

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   .env файл     │────▶│ docker-compose   │────▶│   Контейнеры    │
│ (на хосте)      │     │    .yml          │     │  (environment)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

### Новые переменные безопасности

| Переменная | Где задаётся | Где используется | Описание |
|------------|--------------|------------------|----------|
| `SMTP_RELAY_USERNAME` | `.env` файл | smtp-relay контейнер | Логин для AMS при подключении к SMTP |
| `SMTP_RELAY_PASSWORD` | `.env` файл | smtp-relay контейнер | Пароль для AMS при подключении к SMTP |
| `SMTP_RELAY_SECRET` | `.env` файл | api, sidekiq, smtp-relay | HMAC ключ для подписи запросов |

### Подробное описание

#### 1. SMTP_RELAY_USERNAME и SMTP_RELAY_PASSWORD

**Где задаются:**
- Файл: `.env` на сервере (корень проекта)
- Шаблон: `env.example.txt` (строки 172-173)

**Как настроить в AMS Enterprise:**
```
В настройках AMS укажите:
- SMTP сервер: your-domain.com
- SMTP порт: 2587
- SMTP логин: значение SMTP_RELAY_USERNAME из .env
- SMTP пароль: значение SMTP_RELAY_PASSWORD из .env
- TLS: включен (STARTTLS)
```

**НЕ в Dashboard!** Эти переменные задаются на уровне сервера, не в веб-интерфейсе.

#### 2. SMTP_RELAY_SECRET

**Где задаётся:**
- Файл: `.env` на сервере (корень проекта)
- Шаблон: `env.example.txt` (строка 178)

**Как работает:**
1. SMTP Relay (server.js) при отправке запроса к API подписывает payload HMAC-SHA256
2. API (smtp_controller.rb) проверяет подпись
3. Если подпись неверна - запрос отклоняется

**Генерация:**
```bash
openssl rand -hex 32
```

### Полный процесс настройки

```bash
# 1. Скопируйте шаблон
cp env.example.txt .env

# 2. Отредактируйте .env
nano .env

# 3. Сгенерируйте новые секреты
echo "SMTP_RELAY_USERNAME=smtp_relay"
echo "SMTP_RELAY_PASSWORD=$(openssl rand -base64 24)"
echo "SMTP_RELAY_SECRET=$(openssl rand -hex 32)"

# 4. Перезапустите сервисы
docker compose down
docker compose up -d

# 5. Проверьте логи
docker compose logs smtp-relay | grep -E "(Auth|HMAC)"
```

### Где НЕ задаются эти переменные

❌ **НЕ в Dashboard** - Dashboard используется только для просмотра логов и статистики
❌ **НЕ в Postal UI** - Postal имеет свой отдельный интерфейс
❌ **НЕ в коде** - все секреты только через переменные окружения
❌ **НЕ в docker-compose.yml** - там только ссылки на `.env` через `${VAR}`

### Файлы конфигурации

| Файл | Назначение |
|------|------------|
| `.env` | **ГЛАВНЫЙ файл конфигурации** - все секреты здесь |
| `env.example.txt` | Шаблон с описаниями переменных |
| `docker-compose.yml` | Передаёт переменные из `.env` в контейнеры |
| `config/postal.yml` | Генерируется автоматически (НЕ редактировать!) |

---

## СЛЕДУЮЩИЕ ШАГИ

1. Утвердить план с командой
2. Создать бэкап текущей конфигурации
3. Начать с Фазы 1 - критических исправлений
4. Тестировать каждое изменение в staging
5. Документировать все изменения
