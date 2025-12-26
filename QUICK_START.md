# Quick Start - Email Sender Infrastructure

## 🚀 Быстрый старт (5 минут)

### 1. DNS (ОБЯЗАТЕЛЬНО ПЕРЕД СТАРТОМ!)

Добавьте эти записи в DNS для `linenarrow.com`:

```
linenarrow.com.           IN MX 10 linenarrow.com.
linenarrow.com.           IN A  159.255.39.48
linenarrow.com.           IN TXT "v=spf1 a mx ip4:159.255.39.48 ~all"
_dmarc.linenarrow.com.    IN TXT "v=DMARC1; p=none"
rp.linenarrow.com.        IN CNAME linenarrow.com.
routes.linenarrow.com.    IN CNAME linenarrow.com.
```

### 2. Инициализация Postal

```bash
cd /opt/email-sender

# Инициализация БД
docker compose exec postal postal initialize

# Создать admin
docker compose exec postal postal make-user
# Email: admin@linenarrow.com
# Password: [придумайте]
```

### 3. Настройка Postal Web UI

Откройте `http://linenarrow.com:5000`

1. **Создать Organization**: `LineNarrow`
2. **Создать Mail Server**: `Main Server`, mode=`Live`
3. **DNS Records** → скопировать DKIM запись → добавить в DNS
4. **Credentials** → Create API → скопировать ключ

### 4. Обновить .env

```bash
nano /opt/email-sender/.env

# Вставить API ключ:
POSTAL_API_KEY=XXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Ctrl+X, Y, Enter

docker compose restart api sidekiq smtp-relay
```

### 5. Проверка

```bash
# Все сервисы healthy?
docker compose ps

# Dashboard работает?
curl -I -u admin:DBbNm9X11lHVivPI http://linenarrow.com/dashboard
```

### 6. Создать SMTP Credentials

Dashboard → SMTP Credentials → Generate New

Используйте в AMS:
- Host: `linenarrow.com`
- Port: `587`
- Username: [из Dashboard]
- Password: [из Dashboard]

## ✅ Готово!

Полное руководство: см. `SETUP_GUIDE.md`

## 🔧 Быстрые команды

```bash
# Логи
docker compose logs -f --tail=50

# Перезапуск
docker compose restart postal api

# Статус
docker compose ps

# Миграции
docker compose exec api rails db:migrate

# Консоль Rails
docker compose exec api rails console
```

## 🆘 Проблемы?

**Postal не работает:**
```bash
docker compose logs postal --tail=100
docker compose restart postal
```

**Dashboard 500:**
```bash
docker compose exec api rails db:migrate
docker compose restart api
```

**SMTP не работает:**
- Проверьте DNS: `dig MX linenarrow.com`
- Проверьте DKIM: `dig TXT postal._domainkey.linenarrow.com`
- Проверьте credentials: Dashboard → SMTP Credentials
