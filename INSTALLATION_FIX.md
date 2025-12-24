# ИСПРАВЛЕНИЕ ОШИБОК УСТАНОВКИ НА UBUNTU 22.04

## Обнаруженные критические проблемы

### 1. ❌ Отсутствует файл .env
**Проблема:** Проект не запустится без файла .env с настройками
**Симптом:** Docker контейнеры падают с ошибками подключения к БД

### 2. ❌ Отсутствует config/htpasswd
**Проблема:** Nginx требует этот файл для Basic Auth
**Симптом:** `nginx: [emerg] cannot load certificate`

### 3. ❌ postal.yml содержит не подставленные переменные
**Проблема:** В файле `config/postal.yml` переменные вида `${MARIADB_PASSWORD}` не подставлены
**Симптом:** Postal не может подключиться к MariaDB

### 4. ❌ Отсутствует утилита envsubst
**Проблема:** Ubuntu 22.04 не включает envsubst по умолчанию
**Симптом:** Скрипт `generate-postal-config.sh` падает с ошибкой "command not found"

### 5. ❌ Некорректная команда запуска Postal
**Проблема:** В docker-compose.yml сложная составная команда для Postal может не работать корректно
**Симптом:** Postal контейнер постоянно перезапускается

---

## БЫСТРОЕ ИСПРАВЛЕНИЕ (5 минут)

Выполните эти команды по порядку:

```bash
# 1. Перейдите в директорию проекта
cd /home/user/Postal

# 2. Запустите скрипт предустановки
chmod +x scripts/pre-install.sh
sudo bash scripts/pre-install.sh

# 3. Отредактируйте .env файл (обязательно!)
nano .env
# Измените как минимум:
# - DOMAIN=ваш_домен.com
# - LETSENCRYPT_EMAIL=ваш@email.com
# - ALLOWED_SENDER_DOMAINS=ваш_домен.com
# - AMS_CALLBACK_URL=https://ваш-ams-сервер.com/webhook

# 4. Пересоздайте postal.yml с новыми значениями
source .env
envsubst < config/postal.yml.example > config/postal.yml

# 5. Запустите Docker контейнеры
docker compose up -d

# 6. Дождитесь готовности БД (30-60 секунд)
sleep 60

# 7. Инициализируйте Postal
docker compose exec postal postal initialize

# 8. Создайте первого пользователя Postal
docker compose exec postal postal make-user

# 9. Запустите миграции Rails API
docker compose exec api rails db:create db:migrate

# 10. Проверьте статус
docker compose ps
```

---

## ДЕТАЛЬНАЯ ИНСТРУКЦИЯ ПО ИСПРАВЛЕНИЮ

### Шаг 1: Установка недостающих зависимостей

```bash
# Обновите систему
sudo apt-get update

# Установите необходимые пакеты
sudo apt-get install -y \
    gettext-base \
    apache2-utils \
    curl \
    git \
    openssl

# Установите Docker (если еще не установлен)
curl -fsSL https://get.docker.com | sudo sh

# Установите Docker Compose plugin
sudo apt-get install -y docker-compose-plugin

# Добавьте текущего пользователя в группу docker
sudo usermod -aG docker $USER
newgrp docker
```

### Шаг 2: Создание файла .env

```bash
cd /home/user/Postal

# Скопируйте шаблон
cp env.example.txt .env

# Сгенерируйте безопасные пароли
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" >> /tmp/secrets.txt
echo "MARIADB_PASSWORD=$(openssl rand -hex 16)" >> /tmp/secrets.txt
echo "RABBITMQ_PASSWORD=$(openssl rand -hex 16)" >> /tmp/secrets.txt
echo "SECRET_KEY_BASE=$(openssl rand -hex 32)" >> /tmp/secrets.txt
echo "API_KEY=$(openssl rand -hex 24)" >> /tmp/secrets.txt
echo "POSTAL_SIGNING_KEY=$(openssl rand -hex 32)" >> /tmp/secrets.txt
echo "WEBHOOK_SECRET=$(openssl rand -hex 32)" >> /tmp/secrets.txt

# Покажите сгенерированные секреты
cat /tmp/secrets.txt

# Отредактируйте .env и вставьте эти значения
nano .env
```

**ВАЖНО:** В файле .env обязательно укажите:
- `DOMAIN` - ваш домен (например: send1.example.com)
- `LETSENCRYPT_EMAIL` - email для SSL сертификатов
- `ALLOWED_SENDER_DOMAINS` - домены от которых можно слать письма
- `AMS_CALLBACK_URL` - URL вашего AMS сервера для webhook

### Шаг 3: Создание config/postal.yml

```bash
# Загрузите переменные окружения
set -a
source .env
set +a

# Сгенерируйте postal.yml из шаблона
envsubst < config/postal.yml.example > config/postal.yml

# Проверьте что переменные подставились
grep -v "^\$" config/postal.yml | head -20
```

### Шаг 4: Создание config/htpasswd

```bash
# Вариант 1: С помощью htpasswd (рекомендуется)
htpasswd -b -c config/htpasswd admin ВАШ_ПАРОЛЬ

# Вариант 2: С помощью openssl
HASH=$(openssl passwd -apr1 "ВАШ_ПАРОЛЬ")
echo "admin:$HASH" > config/htpasswd

# Установите правильные права
chmod 600 config/htpasswd
```

### Шаг 5: Запуск сервисов

```bash
# Соберите образы
docker compose build

# Запустите базы данных сначала
docker compose up -d postgres redis mariadb rabbitmq

# Подождите готовности БД
echo "Ожидание готовности баз данных..."
sleep 60

# Проверьте статус БД
docker compose ps

# Инициализируйте Postal (ВАЖНО!)
docker compose run --rm postal postal initialize

# Создайте пользователя Postal
docker compose run --rm postal postal make-user

# Запустите все остальные сервисы
docker compose up -d

# Подождите запуска
sleep 30

# Выполните миграции Rails
docker compose exec api rails db:create
docker compose exec api rails db:migrate
```

### Шаг 6: Проверка работоспособности

```bash
# Проверьте статус всех контейнеров
docker compose ps

# Все контейнеры должны быть в состоянии "Up" или "Up (healthy)"

# Проверьте логи на ошибки
docker compose logs --tail=50 postal
docker compose logs --tail=50 api
docker compose logs --tail=50 nginx

# Проверьте health endpoints
curl http://localhost/api/v1/health
# Должно вернуть: {"status":"ok"}

# Проверьте Postal API
curl http://localhost:5000
# Должна быть HTML страница Postal
```

---

## ЧАСТЫЕ ОШИБКИ И РЕШЕНИЯ

### Ошибка: "postal initialize: command not found"

**Причина:** Postal контейнер не запустился корректно

**Решение:**
```bash
# Пересоздайте контейнер
docker compose down postal
docker compose up -d mariadb rabbitmq
sleep 30
docker compose up -d postal

# Проверьте логи
docker compose logs postal
```

### Ошибка: "Access denied for user 'postal'@'%'"

**Причина:** Неверный пароль MariaDB в postal.yml

**Решение:**
```bash
# Проверьте что пароль в .env и postal.yml совпадают
grep MARIADB_PASSWORD .env
grep password config/postal.yml

# Пересоздайте postal.yml
source .env
envsubst < config/postal.yml.example > config/postal.yml

# Перезапустите Postal
docker compose restart postal
```

### Ошибка: "nginx: cannot load certificate"

**Причина:** Отсутствует файл config/htpasswd

**Решение:**
```bash
# Создайте файл
htpasswd -b -c config/htpasswd admin admin123
chmod 600 config/htpasswd

# Перезапустите nginx
docker compose restart nginx
```

### Ошибка: "rails db:migrate fails"

**Причина:** PostgreSQL не готов или неверные credentials

**Решение:**
```bash
# Проверьте статус PostgreSQL
docker compose exec postgres pg_isready

# Проверьте подключение
docker compose exec api rails runner "ActiveRecord::Base.connection"

# Если ошибка - проверьте DATABASE_URL в .env
grep DATABASE_URL .env
```

---

## ПОЛНАЯ ПЕРЕУСТАНОВКА (если ничего не помогло)

```bash
# 1. Остановите и удалите все контейнеры
docker compose down -v

# 2. Удалите все volumes (ВНИМАНИЕ: удалятся все данные!)
docker volume rm $(docker volume ls -q | grep email_)

# 3. Очистите конфиг файлы
rm -f config/postal.yml config/htpasswd

# 4. Запустите pre-install скрипт заново
sudo bash scripts/pre-install.sh

# 5. Отредактируйте .env
nano .env

# 6. Пересоздайте postal.yml
source .env
envsubst < config/postal.yml.example > config/postal.yml

# 7. Запустите установку с начала
docker compose up -d postgres redis mariadb rabbitmq
sleep 60
docker compose run --rm postal postal initialize
docker compose run --rm postal postal make-user
docker compose up -d
sleep 30
docker compose exec api rails db:create db:migrate
```

---

## ПРОВЕРКА ПОСЛЕ УСТАНОВКИ

```bash
# 1. Все контейнеры должны работать
docker compose ps
# Ожидается: 9 контейнеров в статусе Up

# 2. Health check API
curl http://localhost/api/v1/health
# Ожидается: {"status":"ok"}

# 3. Health check Tracking
curl http://localhost/track/health
# Ожидается: {"status":"ok"}

# 4. Postal Web UI доступен
curl -I http://localhost:5000
# Ожидается: HTTP/1.1 200 OK

# 5. Nginx работает
curl -I http://localhost
# Ожидается: HTTP/1.1 200 OK

# 6. PostgreSQL работает
docker compose exec postgres pg_isready
# Ожидается: accepting connections

# 7. MariaDB работает
docker compose exec mariadb mysql -upostal -p${MARIADB_PASSWORD} -e "SELECT 1"
# Ожидается: 1

# 8. Redis работает
docker compose exec redis redis-cli ping
# Ожидается: PONG

# 9. RabbitMQ работает
docker compose exec rabbitmq rabbitmq-diagnostics check_running
# Ожидается: Runtime check succeeded
```

---

## ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ

### Порты используемые системой:
- `80` - HTTP (Nginx)
- `443` - HTTPS (Nginx)
- `25` - SMTP (Postal)
- `587` - SMTP Submission (Postal)
- `3000` - Rails API (internal)
- `3001` - Tracking service (internal)
- `5000` - Postal Web UI (internal)

### Файлы которые нужно создать вручную:
1. `.env` - конфигурация окружения
2. `config/postal.yml` - конфигурация Postal
3. `config/htpasswd` - пароли для Nginx Basic Auth

### Утилиты которые должны быть установлены:
1. `docker` - контейнеризация
2. `docker compose` - оркестрация контейнеров
3. `envsubst` - подстановка переменных (из пакета gettext-base)
4. `htpasswd` - генерация паролей (из пакета apache2-utils)
5. `openssl` - генерация секретов
6. `curl` - проверка HTTP endpoints

---

## КОНТАКТЫ ПОДДЕРЖКИ

Если проблема не решается:
1. Соберите логи: `docker compose logs > full-logs.txt`
2. Проверьте все файлы конфигурации
3. Создайте issue в репозитории с полным описанием ошибки

**Удачной установки!** 🚀
