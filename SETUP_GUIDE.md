# Email Sender Infrastructure - Руководство по настройке

## 1. ПРЕДВАРИТЕЛЬНЫЕ ТРЕБОВАНИЯ

### DNS Записи (ОБЯЗАТЕЛЬНО!)

Добавьте следующие DNS записи для домена `linenarrow.com`:

```
# MX запись для входящей почты
linenarrow.com.           IN MX 10 linenarrow.com.

# A запись для сервера
linenarrow.com.           IN A  159.255.39.48

# SPF запись (предотвращает спуфинг)
linenarrow.com.           IN TXT "v=spf1 a mx ip4:159.255.39.48 ~all"

# DMARC запись (политика почты)
_dmarc.linenarrow.com.    IN TXT "v=DMARC1; p=none; rua=mailto:admin@linenarrow.com"

# DKIM запись (будет сгенерирована Postal, добавите позже)
# postal._domainkey.linenarrow.com IN TXT "v=DKIM1; ..."

# Return Path поддомен
rp.linenarrow.com.        IN CNAME linenarrow.com.

# Routes поддомен
routes.linenarrow.com.    IN CNAME linenarrow.com.
```

---

## 2. ИНИЦИАЛИЗАЦИЯ POSTAL

### Шаг 1: Инициализация базы данных

```bash
cd /opt/email-sender

# Инициализация БД Postal (создаст таблицы)
docker compose exec postal postal initialize

# Если ошибка - проверьте подключение к MariaDB
docker compose exec mariadb mysql -u postal -p3d13ad32d93c33da6e3c9cc09e3525bca7f51c1a3a5fc908b6bcad451cf4567c -e "SHOW DATABASES;"
```

### Шаг 2: Создание первого администратора

```bash
# Создать admin пользователя
docker compose exec postal postal make-user

# Введите данные:
# Email: admin@linenarrow.com
# First Name: Admin
# Last Name: User
# Password: [ваш безопасный пароль]
```

**ВАЖНО:** Сохраните пароль! Он нужен для входа в веб-интерфейс Postal.

### Шаг 3: Вход в Postal Web UI

Откройте в браузере: `http://linenarrow.com:5000`

- Email: `admin@linenarrow.com`
- Password: [тот что ввели выше]

---

## 3. НАСТРОЙКА POSTAL (через Web UI)

### Шаг 1: Создать организацию

1. Войдите в Postal Web UI
2. Нажмите "Create Organization"
3. Заполните:
   - Name: `LineNarrow`
   - Short Name: `linenarrow` (используется в путях)

### Шаг 2: Создать Mail Server

1. Внутри организации нажмите "New Mail Server"
2. Заполните:
   - Name: `Main Server`
   - Short Name: `main`
   - Mode: `Live` (не Sandbox!)
   - IP Pools: `Default`
   - Allow sender domains: `linenarrow.com`

3. Нажмите "Build server"

### Шаг 3: Настроить DKIM

1. В Mail Server перейдите в "DNS Records"
2. Postal сгенерирует DKIM ключ
3. Скопируйте DKIM запись (формат TXT record)
4. Добавьте её в DNS:

```
postal._domainkey.linenarrow.com IN TXT "v=DKIM1; k=rsa; p=MIGfMA0GCS..."
```

5. Дождитесь распространения DNS (5-10 минут)
6. В Postal нажмите "Check DNS" - все записи должны быть зелёными

### Шаг 4: Получить API ключ

1. В Mail Server перейдите в "Credentials"
2. Нажмите "Create new credentials"
3. Type: `API`
4. Name: `Email Sender API`
5. Скопируйте сгенерированный API ключ

**ВАЖНО:** API ключ показывается только один раз!

Формат: `XXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`

---

## 4. ОБНОВЛЕНИЕ .ENV

Отредактируйте `/opt/email-sender/.env`:

```bash
# Вставьте API ключ из Postal
POSTAL_API_KEY=XXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Проверьте другие настройки
DOMAIN=linenarrow.com
ALLOWED_SENDER_DOMAINS=linenarrow.com
```

Перезапустите сервисы:

```bash
docker compose restart api sidekiq smtp-relay
```

---

## 5. ПРОВЕРКА РАБОТОСПОСОБНОСТИ

### Шаг 1: Проверить все сервисы

```bash
docker compose ps

# Все контейнеры должны быть healthy
```

### Шаг 2: Проверить Dashboard

Откройте: `http://linenarrow.com/dashboard`

- Username: `admin`
- Password: `DBbNm9X11lHVivPI` (из .env)

Проверьте все вкладки:
- ✅ Dashboard
- ✅ Logs
- ✅ SMTP Credentials
- ✅ API Keys
- ✅ Webhooks
- ✅ AI Analytics
- ✅ Settings

### Шаг 3: Создать SMTP Credentials

1. В Dashboard → SMTP Credentials
2. Нажмите "Generate New Credential"
3. Description: `AMS Integration`
4. Rate Limit: `100` emails/min
5. Сохраните Username и Password

**Эти credentials используются для подключения AMS к вашему SMTP серверу!**

---

## 6. НАСТРОЙКА AMS

В AMS Enterprise настройте SMTP:

```
SMTP Host: linenarrow.com
SMTP Port: 587
Security: TLS/STARTTLS
Username: [из SMTP Credentials]
Password: [из SMTP Credentials]
```

---

## 7. ТЕСТИРОВАНИЕ ОТПРАВКИ

### Способ 1: Через Postal Web UI

1. В Postal → Mail Server → "Send Test Message"
2. From: `noreply@linenarrow.com`
3. To: `[ваш email]`
4. Subject: `Test`
5. Body: `Test message`
6. Send

Проверьте inbox и spam.

### Способ 2: Через API

```bash
curl -X POST http://linenarrow.com/api/v1/send \
  -H "Content-Type: application/json" \
  -H "X-API-Key: [ваш API ключ из Dashboard → API Keys]" \
  -d '{
    "from": "noreply@linenarrow.com",
    "to": "test@example.com",
    "subject": "Test Email",
    "html": "<h1>Hello!</h1><p>This is a test.</p>"
  }'
```

### Способ 3: Через SMTP (с credentials)

```bash
# Используя telnet/openssl
openssl s_client -connect linenarrow.com:587 -starttls smtp
```

---

## 8. МОНИТОРИНГ И ЛОГИ

### Просмотр логов

```bash
# Postal логи
docker compose logs postal -f --tail=100

# API логи
docker compose logs api -f --tail=100

# Sidekiq логи (фоновые задачи)
docker compose logs sidekiq -f --tail=100

# SMTP Relay логи
docker compose logs smtp-relay -f --tail=100

# Все сервисы
docker compose logs -f --tail=50
```

### Dashboard Analytics

- Email Logs: `http://linenarrow.com/dashboard/logs`
- Analytics: `http://linenarrow.com/dashboard/analytics`
- Webhooks: `http://linenarrow.com/dashboard/webhooks`

---

## 9. РЕШЕНИЕ ПРОБЛЕМ

### Postal не стартует

```bash
# Проверить логи
docker compose logs postal --tail=100

# Проверить MariaDB
docker compose exec mariadb mysql -u postal -p3d13ad32d93c33da6e3c9cc09e3525bca7f51c1a3a5fc908b6bcad451cf4567c -e "SHOW DATABASES;"

# Переинициализировать
docker compose exec postal postal initialize
```

### Письма не отправляются

1. Проверьте DNS записи: `dig MX linenarrow.com`
2. Проверьте DKIM: `dig TXT postal._domainkey.linenarrow.com`
3. Проверьте Postal Queue: Web UI → Message Queue
4. Проверьте логи: `docker compose logs postal -f`

### SMTP Authentication Failed

1. Проверьте SMTP Credentials в Dashboard
2. Проверьте активность credentials (Active: Yes)
3. Проверьте rate limits

### 500 Error в Dashboard

```bash
# Проверить логи API
docker compose logs api --tail=100

# Проверить PostgreSQL
docker compose exec postgres psql -U email_sender -d email_sender -c "\dt"

# Запустить миграции
docker compose exec api rails db:migrate
```

---

## 10. БЕЗОПАСНОСТЬ

### Важные рекомендации:

1. **Измените пароли по умолчанию** в `.env`
2. **Настройте firewall**:
   ```bash
   ufw allow 22/tcp    # SSH
   ufw allow 80/tcp    # HTTP
   ufw allow 443/tcp   # HTTPS
   ufw allow 25/tcp    # SMTP
   ufw allow 587/tcp   # SMTP Submission
   ufw enable
   ```

3. **SSL/TLS сертификаты**: Let's Encrypt автоматически настроен
4. **Rate Limiting**: Настроен в SMTP Credentials
5. **Webhook Security**: Используйте `WEBHOOK_SECRET` для верификации

---

## 11. ОБСЛУЖИВАНИЕ

### Резервное копирование

```bash
# Backup PostgreSQL
docker compose exec postgres pg_dump -U email_sender email_sender > backup_postgres_$(date +%Y%m%d).sql

# Backup MariaDB (Postal)
docker compose exec mariadb mysqldump -u postal -p3d13ad32d93c33da6e3c9cc09e3525bca7f51c1a3a5fc908b6bcad451cf4567c --all-databases > backup_mariadb_$(date +%Y%m%d).sql

# Backup .env и конфиги
tar -czf backup_configs_$(date +%Y%m%d).tar.gz .env config/
```

### Обновление

```bash
# Обновить образы
docker compose pull

# Перезапустить
docker compose down && docker compose up -d

# Проверить миграции
docker compose exec api rails db:migrate
```

---

## КОНТАКТЫ И ПОДДЕРЖКА

- Dashboard: `http://linenarrow.com/dashboard`
- Postal UI: `http://linenarrow.com:5000`
- API Docs: `http://linenarrow.com/api/v1/docs`

Логи: `/opt/email-sender/` → `docker compose logs`
