# Deployment Guide

## Обзор

Этот документ описывает процесс развёртывания Send Server: локальная установка для разработки и production развёртывание на сервере.

---

## Локальная установка (для разработки)

### Требования

- Docker Desktop (Windows/Mac) или Docker + Docker Compose (Linux)
- Git
- Минимум 4 GB RAM

### Быстрый старт (Local Development)

```bash
# 1. Клонировать репозиторий
git clone <repository-url>
cd email-sender-infrastructure

# 2. Создать .env файл из примера
cp env.example.txt .env

# 3. Отредактировать .env и установить значения для локального тестирования
# Минимальные значения для local dev:
#   DOMAIN=localhost
#   RAILS_ENV=development
#   POSTGRES_PASSWORD=test_password_123
#   MARIADB_PASSWORD=test_password_123
#   RABBITMQ_PASSWORD=test_password_123
#   SECRET_KEY_BASE=<сгенерировать через openssl rand -hex 32>
#   ENCRYPTION_*_KEY=<сгенерировать>
#   DASHBOARD_USERNAME=admin
#   DASHBOARD_PASSWORD=admin
#   SIDEKIQ_WEB_USERNAME=admin
#   SIDEKIQ_WEB_PASSWORD=admin
#   CORS_ORIGINS=*  # или оставить пустым для dev

# 3.1. Генерация config/postal.yml из шаблона
# Postal не поддерживает переменные окружения в YAML файле напрямую.
# Нужно сгенерировать config/postal.yml из шаблона перед запуском.

# Вариант 1: Используя скрипт (рекомендуется)
bash scripts/generate-postal-config.sh

# Вариант 2: Используя envsubst
export $(grep -v '^#' .env | xargs)
envsubst < config/postal.yml.example > config/postal.yml

# Вариант 3: Вручную - скопировать шаблон и заменить ${VAR} на реальные значения
cp config/postal.yml.example config/postal.yml
# Затем отредактировать config/postal.yml и заменить:
#   ${DOMAIN} -> localhost (или ваш домен)
#   ${MARIADB_PASSWORD} -> значение из .env
#   ${RABBITMQ_PASSWORD} -> значение из .env
#   ${SECRET_KEY_BASE} -> значение из .env

# 3.2. Создать файл htpasswd для Nginx Basic Auth
# Файл config/htpasswd необходим для базовой аутентификации в Nginx.
# Если файл отсутствует, контейнер nginx не сможет запуститься.

# Вариант 1: Используя скрипт (рекомендуется)
bash scripts/create-htpasswd.sh admin admin123

# Вариант 2: Используя htpasswd (если установлен)
htpasswd -bc config/htpasswd admin admin123

# Вариант 3: Используя Docker
docker run --rm -v "$PWD/config:/config" httpd:2.4-alpine htpasswd -b -c /config/htpasswd admin admin123

# Вариант 4: Используя openssl
HASH=$(openssl passwd -apr1 admin123)
echo "admin:$HASH" > config/htpasswd
chmod 600 config/htpasswd

# Примечание: По умолчанию создан пример файл с admin/admin123.
# Для production обязательно измените пароль!

# 4. Запустить все сервисы
# Docker Compose автоматически подтянет переменные из .env файла
docker compose up -d

# 5. Дождаться готовности сервисов (миграции выполняются автоматически через entrypoint)
# Проверить статус:
docker compose ps

# 6. Проверить логи API (миграции должны быть выполнены)
docker compose logs api | grep -i migration

# 7. Создать API ключ
docker compose exec api rails runner "key = ApiKey.generate(name: 'Local Test'); puts key.raw_key"

# 8. Проверить health
curl http://localhost/api/v1/health
```

**Важно:**
- Миграции выполняются автоматически при старте контейнера `api` через `docker-entrypoint.sh`
- Контейнер `sidekiq` также выполняет миграции перед запуском (использует тот же entrypoint)
- Healthchecks для postgres и redis гарантируют, что базы данных готовы перед стартом приложения

### Локальные порты

- `80` — Nginx (HTTP)
- `443` — Nginx (HTTPS, если настроен SSL)
- `3000` — Rails API (напрямую)
- `3001` — Tracking Service (напрямую)
- `2525` — SMTP Relay (Haraka) для приёма от AMS
- `5000` — Postal Web UI

### Локальная конфигурация .env

```env
DOMAIN=localhost
RAILS_ENV=development
POSTGRES_PASSWORD=test_password_123
MARIADB_PASSWORD=test_password_123
RABBITMQ_PASSWORD=test_password_123
SECRET_KEY_BASE=test_secret_key_base_64_chars_long_for_rails_application_1234567890123456789012345678901234567890123456789012345678901234
ENCRYPTION_PRIMARY_KEY=test_encryption_primary_key_32_chars
ENCRYPTION_DETERMINISTIC_KEY=test_encryption_deterministic_key_32_chars
ENCRYPTION_KEY_DERIVATION_SALT=test_encryption_salt_32_chars
SMTP_RELAY_API_KEY=test_smtp_relay_key_32_chars
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=admin
```

### Тестирование SMTP Relay локально

```powershell
# PowerShell (Windows)
$smtp = New-Object System.Net.Mail.SmtpClient("localhost", 2525)
$smtp.EnableSsl = $false
$mail = New-Object System.Net.Mail.MailMessage("test@example.com", "recipient@example.com", "Test Subject", "<html><body><h1>Test</h1></body></html>")
$mail.IsBodyHtml = $true
$smtp.Send($mail)
```

```python
# Python
import smtplib
from email.mime.text import MIMEText

msg = MIMEText("<html><body><h1>Test</h1></body></html>", "html")
msg["From"] = "test@example.com"
msg["To"] = "recipient@example.com"
msg["Subject"] = "Test Subject"

smtp = smtplib.SMTP("localhost", 2525)
smtp.send_message(msg)
smtp.quit()
```

---

## Production развёртывание

## Требования

### Сервер

| Параметр | Минимум | Рекомендуется |
|----------|---------|---------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Disk | 50 GB SSD | 100 GB SSD |
| Network | 100 Mbps | 1 Gbps |

### DNS

Перед установкой настройте DNS:

```
send1.example.com.     A      1.2.3.4
mail.send1.example.com A      1.2.3.4
```

### Firewall (провайдер)

Открытые порты:
- `22` — SSH
- `80` — HTTP (для Let's Encrypt)
- `443` — HTTPS
- `25` — SMTP (outbound)

---

## Способы установки

### Способ 1: Автоматический скрипт (рекомендуется)

```bash
# На свежем сервере Ubuntu 22.04
curl -sSL https://raw.githubusercontent.com/YOUR_REPO/install.sh | sudo bash
```

Скрипт:
1. Установит Docker и Docker Compose
2. Спросит параметры (домен, API ключ AMS)
3. Сгенерирует конфигурацию
4. Запустит все сервисы
5. Настроит SSL

### Способ 2: Ручная установка

Следуйте шагам ниже.

---

## Ручная установка

### Шаг 1: Подготовка сервера

```bash
# Обновление системы
apt update && apt upgrade -y

# Установка базовых утилит
apt install -y curl wget git htop nano ufw fail2ban

# Настройка firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 25/tcp
ufw enable

# Настройка fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

### Шаг 2: Установка Docker

```bash
# Добавление репозитория Docker
curl -fsSL https://get.docker.com | sh

# Добавление пользователя в группу docker
usermod -aG docker $USER

# Запуск Docker
systemctl enable docker
systemctl start docker

# Проверка
docker --version
docker compose version
```

### Шаг 3: Создание директории

```bash
mkdir -p /opt/email-sender
cd /opt/email-sender
```

### Шаг 4: Создание .env файла

```bash
cat > .env << 'EOF'
# ===========================================
# ОСНОВНЫЕ НАСТРОЙКИ
# ===========================================

# Домен сервера
DOMAIN=send1.example.com

# Email для Let's Encrypt
LETSENCRYPT_EMAIL=admin@example.com

# ===========================================
# СЕКРЕТЫ (генерируются автоматически)
# ===========================================

# Пароль PostgreSQL
POSTGRES_PASSWORD=GENERATE_RANDOM_32_HEX

# Пароль MariaDB
MARIADB_PASSWORD=GENERATE_RANDOM_32_HEX

# Пароль RabbitMQ
RABBITMQ_PASSWORD=GENERATE_RANDOM_32_HEX

# Rails secret key
SECRET_KEY_BASE=GENERATE_RANDOM_64_HEX

# API ключ для AMS (показать один раз!)
API_KEY=GENERATE_RANDOM_48_HEX

# ===========================================
# НАСТРОЙКИ AMS
# ===========================================

# URL для webhooks обратно в AMS
AMS_CALLBACK_URL=https://ams.example.com/api/webhooks/send_server

# API ключ для аутентификации в AMS
AMS_API_KEY=your_ams_api_key

# ===========================================
# НАСТРОЙКИ EMAIL
# ===========================================

# Разрешённые домены отправителя (через запятую)
ALLOWED_SENDER_DOMAINS=example.com,mail.example.com

# Лимит писем в день
DAILY_LIMIT=50000

# ===========================================
# CORS
# ===========================================

# Разрешенные домены для CORS (через запятую)
# В production: обязательно задать явно, иначе CORS будет отключен
# В development/test: по умолчанию разрешены все (*), если не задано
# Пример: https://ams.example.com,https://admin.example.com
CORS_ORIGINS=https://ams.example.com

# ===========================================
# POSTAL
# ===========================================

# Signing key для Postal (генерируется)
POSTAL_SIGNING_KEY=GENERATE_RANDOM_HEX

EOF

# Генерация секретов
sed -i "s/GENERATE_RANDOM_32_HEX/$(openssl rand -hex 16)/g" .env
sed -i "s/GENERATE_RANDOM_64_HEX/$(openssl rand -hex 32)/g" .env
sed -i "s/GENERATE_RANDOM_48_HEX/$(openssl rand -hex 24)/g" .env
```

### Шаг 5: Клонирование репозитория

```bash
# Клонировать репозиторий
git clone <repository-url> /opt/email-sender
cd /opt/email-sender

# Или скопировать файлы проекта в /opt/email-sender
```

### Шаг 6: Создание docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # ===========================================
  # DATABASES
  # ===========================================
  
  postgres:
    image: postgres:15-alpine
    container_name: email_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: email_sender
      POSTGRES_USER: email_sender
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U email_sender"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: email_redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  mariadb:
    image: mariadb:10.11
    container_name: email_mariadb
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MARIADB_PASSWORD}
      MYSQL_DATABASE: postal
      MYSQL_USER: postal
      MYSQL_PASSWORD: ${MARIADB_PASSWORD}
    volumes:
      - mariadb_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: email_rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: postal
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD}
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_running"]
      interval: 30s
      timeout: 10s
      retries: 5

  # ===========================================
  # APPLICATION
  # ===========================================

  api:
    build:
      context: ./services/api
      dockerfile: Dockerfile
    container_name: email_api
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      RAILS_ENV: production
      DATABASE_URL: postgres://email_sender:${POSTGRES_PASSWORD}@postgres/email_sender
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      POSTAL_API_URL: http://postal:5000
      POSTAL_API_KEY: ${POSTAL_SIGNING_KEY}
      AMS_CALLBACK_URL: ${AMS_CALLBACK_URL}
      AMS_API_KEY: ${AMS_API_KEY}
      ALLOWED_SENDER_DOMAINS: ${ALLOWED_SENDER_DOMAINS}
      DAILY_LIMIT: ${DAILY_LIMIT}
      DOMAIN: ${DOMAIN}
    volumes:
      - api_logs:/app/log
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  sidekiq:
    build:
      context: ./services/api
      dockerfile: Dockerfile
    container_name: email_sidekiq
    restart: unless-stopped
    command: bundle exec sidekiq -C config/sidekiq.yml
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      api:
        condition: service_healthy
    environment:
      RAILS_ENV: production
      DATABASE_URL: postgres://email_sender:${POSTGRES_PASSWORD}@postgres/email_sender
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      POSTAL_API_URL: http://postal:5000
      POSTAL_API_KEY: ${POSTAL_SIGNING_KEY}
      AMS_CALLBACK_URL: ${AMS_CALLBACK_URL}
    volumes:
      - api_logs:/app/log

  tracking:
    build:
      context: ./services/tracking
      dockerfile: Dockerfile
    container_name: email_tracking
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://email_sender:${POSTGRES_PASSWORD}@postgres/email_sender
      REDIS_URL: redis://redis:6379/0
      AMS_CALLBACK_URL: ${AMS_CALLBACK_URL}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ===========================================
  # POSTAL
  # ===========================================

  postal:
    image: ghcr.io/postalserver/postal:latest
    container_name: email_postal
    restart: unless-stopped
    depends_on:
      mariadb:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    ports:
      - "25:25"
    environment:
      POSTAL_SIGNING_KEY: ${POSTAL_SIGNING_KEY}
    volumes:
      - ./config/postal.yml:/opt/postal/config/postal.yml:ro
      - postal_data:/opt/postal/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  # ===========================================
  # NGINX
  # ===========================================

  nginx:
    image: nginx:alpine
    container_name: email_nginx
    restart: unless-stopped
    depends_on:
      - api
      - tracking
      - postal
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
      - certbot_data:/var/www/certbot
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 60s
      timeout: 10s
      retries: 3

  # ===========================================
  # CERTBOT (SSL)
  # ===========================================

  certbot:
    image: certbot/certbot
    container_name: email_certbot
    volumes:
      - ./certs:/etc/letsencrypt
      - certbot_data:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

volumes:
  postgres_data:
  redis_data:
  mariadb_data:
  rabbitmq_data:
  postal_data:
  api_logs:
  certbot_data:

networks:
  default:
    name: email_network
EOF
```

### Шаг 6: Конфигурация Nginx

```bash
mkdir -p config

cat > config/nginx.conf << 'EOF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/s;
    limit_req_zone $binary_remote_addr zone=tracking:10m rate=1000r/s;

    # Upstream definitions
    upstream api {
        server api:3000;
        keepalive 32;
    }

    upstream tracking {
        server tracking:3001;
        keepalive 32;
    }

    upstream postal {
        server postal:5000;
        keepalive 16;
    }

    # HTTP redirect to HTTPS
    server {
        listen 80;
        server_name _;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://$host$request_uri;
        }
    }

    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name ${DOMAIN};

        ssl_certificate /etc/nginx/certs/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/nginx/certs/live/${DOMAIN}/privkey.pem;
        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:50m;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        ssl_prefer_server_ciphers off;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # API endpoints
        location /api/ {
            limit_req zone=api burst=50 nodelay;
            
            proxy_pass http://api;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";
            
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }

        # Tracking endpoints (high traffic)
        location /track/ {
            limit_req zone=tracking burst=500 nodelay;
            
            proxy_pass http://tracking;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Connection "";
            
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
        }

        # Postal web UI
        location /postal/ {
            auth_basic "Restricted";
            auth_basic_user_file /etc/nginx/.htpasswd;
            
            proxy_pass http://postal/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        # Sidekiq web UI (optional)
        location /sidekiq/ {
            auth_basic "Restricted";
            auth_basic_user_file /etc/nginx/.htpasswd;
            
            proxy_pass http://api/sidekiq/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF
```

### Шаг 7: Настройка SMTP Relay (Haraka)

SMTP Relay уже включён в docker-compose.yml. Проверьте настройки:

```bash
# Проверка конфигурации Haraka
cat services/smtp-relay/config/smtp.ini
cat services/smtp-relay/config/auth_flat_file.ini

# В .env должен быть установлен:
SMTP_RELAY_API_KEY=your_api_key_here
```

**Важно:** Порт 2525 должен быть открыт в firewall для приёма писем от AMS.

### Шаг 8: Конфигурация Postal

```bash
cat > config/postal.yml << 'EOF'
# Postal Configuration

general:
  use_ip_pools: false

web:
  host: ${DOMAIN}
  protocol: https

main_db:
  host: mariadb
  port: 3306
  username: postal
  password: ${MARIADB_PASSWORD}
  database: postal

message_db:
  host: mariadb
  port: 3306
  username: postal
  password: ${MARIADB_PASSWORD}
  prefix: postal

rabbitmq:
  host: rabbitmq
  port: 5672
  username: postal
  password: ${RABBITMQ_PASSWORD}
  vhost: postal

smtp_server:
  port: 25
  log_connect: true

dns:
  mx_records:
    - ${DOMAIN}
  smtp_server_hostname: ${DOMAIN}
  spf_include: spf.${DOMAIN}
  return_path: rp.${DOMAIN}
  route_domain: routes.${DOMAIN}
  track_domain: track.${DOMAIN}
  dkim_identifier: postal

logging:
  rails_log: true
  
rails:
  secret_key: ${SECRET_KEY_BASE}
EOF
```

### Шаг 9: Запуск (Production-like)

**Важно:** Docker Compose автоматически подтягивает переменные из `.env` файла в корне проекта.

```bash
# 1. Сборка образов
docker compose build

# 2. Запуск баз данных (postgres, redis, mariadb, rabbitmq)
# Healthchecks гарантируют готовность БД перед стартом приложения
docker compose up -d postgres redis mariadb rabbitmq

# 3. Ожидание готовности баз данных (healthchecks)
# Проверить статус:
docker compose ps

# 4. Инициализация Postal (если первый запуск)
docker compose run --rm postal postal initialize-db || true
docker compose run --rm postal postal make-user || true

# 5. Запуск всех сервисов
# Миграции выполняются автоматически через docker-entrypoint.sh
# для контейнеров api и sidekiq перед их стартом
docker compose up -d

# 6. Проверка статуса всех сервисов
docker compose ps

# 7. Проверка логов (миграции должны быть выполнены)
docker compose logs api | grep -i migration
docker compose logs sidekiq | grep -i migration

# 8. Проверка health endpoints
curl http://localhost/api/v1/health
curl http://localhost:5000/health  # Postal

# 9. Создание API ключа
docker compose exec api rails runner "key = ApiKey.generate(name: 'Production'); puts 'API Key: ' + key[1]"
```

**Примечания:**
- Миграции выполняются автоматически при старте контейнеров `api` и `sidekiq` через `docker-entrypoint.sh`
- Healthchecks для `postgres` и `redis` гарантируют, что базы данных готовы перед стартом приложения
- Переменные окружения подтягиваются из `.env` файла автоматически (Docker Compose feature)
- Если миграции уже выполнены, они пропускаются (Rails db:migrate идемпотентен)

---

## Команды запуска

### Local Development

```bash
# 1. Создать .env из примера
cp env.example.txt .env

# 2. Отредактировать .env (установить значения для локальной разработки)

# 3. Запустить все сервисы
docker compose up -d

# 4. Проверить статус
docker compose ps

# 5. Просмотр логов
docker compose logs -f api

# 6. Остановка
docker compose down

# 7. Пересборка после изменений кода
docker compose build api
docker compose up -d api
```

### Production-like

```bash
# 1. Создать .env с production значениями
cp env.example.txt .env
# Отредактировать .env со всеми production секретами

# 2. Сборка образов
docker compose build

# 3. Запуск баз данных
docker compose up -d postgres redis mariadb rabbitmq

# 4. Ожидание готовности (healthchecks)
sleep 30
docker compose ps

# 5. Инициализация Postal (первый запуск)
docker compose run --rm postal postal initialize-db || true
docker compose run --rm postal postal make-user || true

# 6. Запуск всех сервисов
# Миграции выполняются автоматически через entrypoint
docker compose up -d

# 7. Проверка статуса
docker compose ps

# 8. Проверка логов миграций
docker compose logs api | grep -i migration
docker compose logs sidekiq | grep -i migration

# 9. Проверка health
curl http://localhost/api/v1/health

# 10. Создание API ключа
docker compose exec api rails runner "key = ApiKey.generate(name: 'Production'); puts 'API Key: ' + key[1]"
```

**Важные моменты:**
- `.env` файл должен быть в корне проекта (не в git!)
- Docker Compose автоматически подтягивает переменные из `.env`
- Миграции выполняются автоматически при старте `api` и `sidekiq`
- Healthchecks гарантируют готовность зависимостей перед стартом

### Шаг 10: SSL сертификат

```bash
# Получение сертификата
docker compose run --rm certbot certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email ${LETSENCRYPT_EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d ${DOMAIN}

# Перезапуск nginx
docker compose restart nginx
```

### Шаг 11: Настройка Postal

После запуска Postal необходимо:

1. **Создать organization и server:**
```bash
docker compose exec postal postal initialize
docker compose exec postal postal make-user
```

2. **Получить API ключи:**
   - Войдите в Postal Web UI: `https://send1.example.com/postal/`
   - Создайте organization
   - Создайте server
   - Скопируйте API ключ в `.env` как `POSTAL_API_KEY`

3. **Настроить DKIM:**
```bash
docker compose exec postal postal default-dkim-record
# Скопируйте TXT запись в DNS
```

### Шаг 12: Настройка AMS Enterprise

В AMS Enterprise настройте SMTP relay:

1. Откройте настройки SMTP
2. Добавьте новый SMTP сервер:
   - **Host:** `send1.example.com`
   - **Port:** `2525`
   - **Authentication:** LOGIN
   - **Username:** значение из `SMTP_RELAY_API_KEY`
   - **Password:** значение из `SMTP_RELAY_API_KEY`
3. Сохраните настройки

### Шаг 13: DNS записи

После установки настройте DNS:

```
# A запись (основная)
send1.example.com.     A      1.2.3.4

# MX запись (для bounce)
send1.example.com.     MX     10 send1.example.com.

# SPF запись
send1.example.com.     TXT    "v=spf1 ip4:1.2.3.4 -all"

# DKIM запись (получить ключ командой: docker compose exec postal postal default-dkim-record)
postal._domainkey.send1.example.com.     TXT    "v=DKIM1; k=rsa; p=MIG..."

# DMARC запись
_dmarc.send1.example.com.     TXT    "v=DMARC1; p=reject; rua=mailto:dmarc@example.com"

# PTR запись (настраивается у хостера)
4.3.2.1.in-addr.arpa.     PTR    send1.example.com.
```

---

## Проверка установки

### 1. Проверка сервисов

```bash
docker compose ps

# Ожидаемый результат:
# NAME              STATUS
# email_api         Up (healthy)
# email_nginx       Up
# email_postgres    Up (healthy)
# email_postal      Up (healthy)
# email_rabbitmq    Up (healthy)
# email_redis       Up (healthy)
# email_sidekiq     Up
# email_tracking    Up (healthy)
```

### 2. Проверка API

```bash
# Health check
curl https://send1.example.com/api/v1/health

# Ожидаемый результат:
# {"status":"healthy","components":{"database":"ok",...}}
```

### 3. Проверка отправки

```bash
curl -X POST https://send1.example.com/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@gmail.com",
    "template_id": "test",
    "from_name": "Test",
    "from_email": "test@send1.example.com",
    "subject": "Test Email",
    "variables": {},
    "tracking": {"campaign_id": "test", "message_id": "test_001"}
  }'
```

---

## Обновление

```bash
cd /opt/email-sender

# Получение обновлений
git pull

# Пересборка образов
docker compose build

# Перезапуск с минимальным простоем
docker compose up -d --no-deps api sidekiq tracking

# Проверка
docker compose ps
docker compose logs -f --tail=100
```

---

## Бэкап

### Автоматический бэкап (cron)

```bash
# /etc/cron.d/email-sender-backup
0 * * * * root /opt/email-sender/scripts/backup.sh >> /var/log/email-backup.log 2>&1
```

### Скрипт бэкапа

```bash
#!/bin/bash
# /opt/email-sender/scripts/backup.sh

BACKUP_DIR="/opt/backups/email-sender"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p ${BACKUP_DIR}

# PostgreSQL
docker compose exec -T postgres pg_dump -U email_sender email_sender > ${BACKUP_DIR}/postgres_${DATE}.sql

# Redis
docker compose exec -T redis redis-cli BGSAVE
docker cp email_redis:/data/dump.rdb ${BACKUP_DIR}/redis_${DATE}.rdb

# Конфиги
tar -czf ${BACKUP_DIR}/config_${DATE}.tar.gz /opt/email-sender/.env /opt/email-sender/config/

# Удаление старых бэкапов (старше 7 дней)
find ${BACKUP_DIR} -type f -mtime +7 -delete

echo "Backup completed: ${DATE}"
```

---

## Развертывание на сервере с ограниченными ресурсами (2GB RAM)

### Оптимизация для маломощных серверов

Проект оптимизирован для работы на серверах с ограниченной памятью (2GB RAM). Все настройки уже применены в `docker-compose.yml` и конфигурационных файлах.

#### Распределение памяти

| Сервис | Лимит памяти | Резерв |
|--------|-------------|--------|
| PostgreSQL | 350MB | 200MB |
| Redis | 250MB | 150MB |
| MariaDB | 300MB | 200MB |
| RabbitMQ | 200MB | 100MB |
| API (Puma) | 400MB | 250MB |
| Sidekiq | 250MB | 150MB |
| Tracking | 150MB | 100MB |
| Postal | 350MB | 200MB |
| Nginx | ~50MB | - |
| **Итого** | **~2.1GB** | **~1.2GB** |

#### Оптимизации

**PostgreSQL:**
- `shared_buffers`: 128MB (вместо дефолтных 128MB)
- `effective_cache_size`: 256MB
- `work_mem`: 4MB
- `maintenance_work_mem`: 64MB

**Redis:**
- `maxmemory`: 200MB (вместо 256MB)
- Политика: `allkeys-lru`

**MariaDB:**
- `innodb-buffer-pool-size`: 200MB
- `max-connections`: 50

**RabbitMQ:**
- `RABBITMQ_VM_MEMORY_HIGH_WATERMARK`: 0.15 (15% от доступной памяти)

**Puma (Rails API):**
- Workers: 1 (вместо 2)
- Threads: 5 (максимум)

**Sidekiq:**
- Concurrency: 5 (вместо 10)

#### Рекомендации

1. **Мониторинг памяти:**
   ```bash
   # Проверка использования памяти контейнерами
   docker stats
   
   # Проверка общей памяти системы
   free -h
   ```

2. **При нехватке памяти:**
   - Уменьшите `SIDEKIQ_CONCURRENCY` до 3
   - Уменьшите `RAILS_MAX_THREADS` до 3
   - Уменьшите лимиты памяти для менее критичных сервисов

3. **Оптимизация диска:**
   - Используйте SSD для лучшей производительности
   - Настройте ротацию логов
   - Регулярно очищайте старые данные

4. **Масштабирование:**
   - При росте нагрузки рассмотрите увеличение RAM до 4GB
   - Для высоконагруженных систем рекомендуется 8GB+

#### Проверка производительности

```bash
# Проверка использования ресурсов
docker stats --no-stream

# Проверка логов на ошибки нехватки памяти
docker compose logs | grep -i "out of memory\|oom\|killed"

# Мониторинг производительности PostgreSQL
docker compose exec postgres psql -U email_sender -d email_sender -c "SELECT * FROM pg_stat_activity;"
```

---

## Мониторинг

### Логи

```bash
# Все логи
docker compose logs -f

# Только API
docker compose logs -f api

# Только ошибки
docker compose logs -f 2>&1 | grep -i error
```

### Метрики

Для production рекомендуется установить:
- **Prometheus** — сбор метрик
- **Grafana** — визуализация
- **Alertmanager** — алерты

---

## Устранение неполадок

### Сервис не запускается

```bash
# Посмотреть логи
docker compose logs SERVICE_NAME

# Перезапустить
docker compose restart SERVICE_NAME

# Пересоздать
docker compose up -d --force-recreate SERVICE_NAME
```

### База данных не подключается

```bash
# Проверить статус
docker compose exec postgres pg_isready

# Проверить пароль в .env
cat .env | grep POSTGRES_PASSWORD

# Войти в PostgreSQL
docker compose exec postgres psql -U email_sender
```

### SSL не работает

```bash
# Проверить сертификаты
ls -la certs/live/${DOMAIN}/

# Обновить сертификат
docker compose run --rm certbot certbot renew

# Перезапустить nginx
docker compose restart nginx
```

