# БЫСТРЫЙ СТАРТ НА UBUNTU 22.04

## За 10 минут до рабочей системы

### Предварительные требования
- Ubuntu 22.04 LTS (чистая установка)
- Root доступ или sudo
- Минимум 2GB RAM
- 20GB свободного места на диске
- Доменное имя (опционально для тестирования)

---

## КОМАНДЫ ДЛЯ КОПИРОВАНИЯ

Просто копируйте и выполняйте блоки команд по порядку:

### 1️⃣ Клонирование репозитория (если еще не сделано)

```bash
cd /home/user
# Если папка Postal уже есть - пропустите этот шаг
# git clone https://github.com/your-repo/email-sender-infrastructure.git Postal
cd Postal
```

### 2️⃣ Запуск автоматической предустановки

```bash
# Этот скрипт:
# - Создаст .env с автогенерированными паролями
# - Установит envsubst (если нужно)
# - Создаст config/postal.yml
# - Создаст config/htpasswd
sudo bash scripts/pre-install.sh
```

### 3️⃣ Настройка .env (ОБЯЗАТЕЛЬНО!)

```bash
# Откройте .env в редакторе
nano .env

# Измените эти значения:
# DOMAIN=linenarrow.com              ← ваш домен
# LETSENCRYPT_EMAIL=admin@linenarrow.com  ← ваш email
# ALLOWED_SENDER_DOMAINS=linenarrow.com   ← домены для отправки
# AMS_CALLBACK_URL=https://your-ams.com/webhook  ← URL AMS сервера

# Сохраните: Ctrl+O, Enter, Ctrl+X
```

### 4️⃣ Обновление postal.yml с новыми данными

```bash
# Загрузите переменные из .env и пересоздайте postal.yml
source .env
envsubst < config/postal.yml.example > config/postal.yml

# Проверьте что домен подставился правильно
grep "host:" config/postal.yml
```

### 5️⃣ Запуск Docker контейнеров

```bash
# Запустите все сервисы
docker compose up -d

# Посмотрите логи (Ctrl+C для выхода)
docker compose logs -f
```

### 6️⃣ Ожидание готовности БД

```bash
# Подождите 60 секунд пока базы данных инициализируются
echo "Ожидание готовности баз данных..."
sleep 60

# Проверьте что БД готовы
docker compose exec postgres pg_isready
docker compose exec mariadb mysql -upostal -p${MARIADB_PASSWORD} -e "SELECT 1"
docker compose exec redis redis-cli ping
```

### 7️⃣ Инициализация Postal

```bash
# Инициализируйте базу данных Postal
docker compose exec postal postal initialize

# Создайте первого пользователя (следуйте инструкциям на экране)
docker compose exec postal postal make-user
# Введите:
# - Email: admin@yourdomain.com
# - First name: Admin
# - Last name: User
# - Password: ваш_пароль
```

### 8️⃣ Инициализация Rails API

```bash
# Создайте базу данных и выполните миграции
docker compose exec api rails db:create db:migrate

# Создайте API ключ для AMS
docker compose exec api rails runner "
  api_key, raw_key = ApiKey.generate(name: 'AMS Production')
  puts '='*50
  puts 'API KEY (сохраните его!):'
  puts raw_key
  puts '='*50
"
```

### 9️⃣ Проверка работоспособности

```bash
# Проверьте статус всех контейнеров
docker compose ps

# Проверьте API health
curl http://localhost/api/v1/health

# Проверьте tracking health
curl http://localhost/track/health

# Проверьте Postal web interface
curl -I http://localhost:5000
```

### 🎉 ГОТОВО!

Если все команды выполнились без ошибок, система работает!

---

## ЧТО ДАЛЬШЕ?

### Доступные URL:
- **API**: http://localhost/api/v1/
- **Tracking**: http://localhost/track/
- **Health check**: http://localhost/health
- **Postal Web UI**: http://localhost:5000

### Тестовая отправка письма:

```bash
# Замените YOUR_API_KEY на ключ из шага 8
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "html_body": "<html><body><h1>Test Email</h1></body></html>",
    "from_name": "Test Sender",
    "from_email": "sender@linenarrow.com",
    "subject": "Test Email",
    "tracking": {
      "campaign_id": "test_campaign",
      "message_id": "test_msg_001"
    }
  }'
```

### Настройка DNS записей:

После успешного запуска настройте DNS:

```
# A запись
linenarrow.com.    IN  A      ВАШ_IP_АДРЕС

# MX запись
linenarrow.com.    IN  MX     10 linenarrow.com.

# SPF запись
linenarrow.com.    IN  TXT    "v=spf1 ip4:ВАШ_IP -all"

# DKIM запись (получите из Postal)
postal._domainkey.linenarrow.com. IN TXT "DKIM_KEY_FROM_POSTAL"
```

Получить DKIM ключ:
```bash
docker compose exec postal postal default-dkim-record
```

### Настройка SSL (Let's Encrypt):

```bash
# Убедитесь что домен указывает на ваш сервер (проверьте DNS)
dig linenarrow.com

# Получите SSL сертификат
docker compose run --rm certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email admin@linenarrow.com \
  --agree-tos \
  --no-eff-email \
  -d linenarrow.com

# Перезапустите nginx
docker compose restart nginx
```

---

## ПОЛЕЗНЫЕ КОМАНДЫ

### Просмотр логов:
```bash
# Все логи
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f api
docker compose logs -f postal
docker compose logs -f nginx
```

### Перезапуск сервисов:
```bash
# Перезапустить все
docker compose restart

# Перезапустить конкретный сервис
docker compose restart api
```

### Остановка и удаление:
```bash
# Остановить все
docker compose down

# Остановить и удалить volumes (УДАЛИТ ВСЕ ДАННЫЕ!)
docker compose down -v
```

### Обновление:
```bash
# Получить последние изменения из git
git pull

# Пересобрать образы
docker compose build

# Перезапустить с новыми образами
docker compose up -d
```

---

## РЕШЕНИЕ ПРОБЛЕМ

### Если контейнер не запускается:

```bash
# Посмотрите логи конкретного контейнера
docker compose logs postal

# Проверьте конфигурацию
docker compose config

# Пересоздайте контейнер
docker compose up -d --force-recreate postal
```

### Если ошибки подключения к БД:

```bash
# Проверьте что БД запущены
docker compose ps postgres mariadb redis

# Проверьте пароли в .env
cat .env | grep PASSWORD

# Пересоздайте postal.yml
source .env
envsubst < config/postal.yml.example > config/postal.yml

# Перезапустите сервисы
docker compose restart postal api
```

### Если Nginx не запускается:

```bash
# Проверьте что htpasswd существует
ls -la config/htpasswd

# Если нет - создайте
htpasswd -b -c config/htpasswd admin admin123

# Проверьте конфигурацию nginx
docker compose exec nginx nginx -t

# Перезапустите
docker compose restart nginx
```

---

## МОНИТОРИНГ

### Проверка ресурсов:
```bash
# Использование памяти и CPU
docker stats

# Использование дискового пространства
docker system df

# Размер volumes
docker volume ls
du -sh /var/lib/docker/volumes/email_*
```

### Health checks:
```bash
# Проверка всех health endpoints
curl http://localhost/api/v1/health
curl http://localhost/track/health
curl http://localhost:5000/health

# Проверка состояния контейнеров
docker compose ps
```

---

## БЭКАП

### Создание резервной копии:
```bash
# Остановите контейнеры
docker compose down

# Создайте бэкап volumes
sudo tar -czf backup-$(date +%Y%m%d).tar.gz \
  /var/lib/docker/volumes/email_postgres_data \
  /var/lib/docker/volumes/email_mariadb_data \
  /var/lib/docker/volumes/email_redis_data

# Сохраните конфигурацию
tar -czf backup-config-$(date +%Y%m%d).tar.gz .env config/

# Запустите контейнеры обратно
docker compose up -d
```

### Восстановление из бэкапа:
```bash
# Остановите контейнеры
docker compose down -v

# Восстановите volumes
sudo tar -xzf backup-20241224.tar.gz -C /

# Восстановите конфигурацию
tar -xzf backup-config-20241224.tar.gz

# Запустите контейнеры
docker compose up -d
```

---

**Поддержка:** Если возникли проблемы, см. INSTALLATION_FIX.md для детальных инструкций.
