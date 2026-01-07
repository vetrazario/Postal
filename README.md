# Email Sender Infrastructure

## Обзор проекта

Это инфраструктурный проект для массовой отправки email через распределённые серверы. Система состоит из:

1. **AMS Enterprise** — центр управления (уже есть, не разрабатываем)
2. **Send Server** — сервер отправки (Rails API + Postal) — **ЭТО РАЗРАБАТЫВАЕМ**

## Архитектура

```
AMS Enterprise ──SMTP──► Send Server 1 ──► Postal ──► Internet
                   ├──► Send Server 2 ──► Postal ──► Internet
                   └──► Send Server N ──► Postal ──► Internet
```

## Что должен делать Send Server

1. Принимать готовые HTML письма от AMS через SMTP Relay (порт 2525)
2. Модифицировать письма: добавлять трекинг (открытия, клики)
3. Генерировать заголовки от имени Send Server (скрывая AMS)
4. Отправлять через Postal
5. Сообщать статусы обратно в AMS через webhooks

## Структура репозитория

```
email-sender-infrastructure/
├── docs/                          # Документация
│   ├── ARCHITECTURE.md            # Архитектура, Data Flow, DB Schema, Integration
│   ├── API.md                     # Спецификация REST API
│   ├── DEPLOYMENT.md              # Локальная установка и Production развёртывание
│   ├── SECURITY.md                # Безопасность
│   ├── TROUBLESHOOTING.md         # Решение проблем
│   └── BOUNCE_HANDLING.md         # Обработка bounce и отказов
│
├── CHANGELOG.md                   # История изменений и исправлений
├── SETUP_GUIDE.md                 # Руководство по установке
├── QUICK_START.md                 # Быстрый старт
└── TESTING_GUIDE.md               # Руководство по тестированию
│
├── services/                      # Сервисы (код)
│   ├── api/                       # Rails API
│   ├── tracking/                  # Tracking сервис (Sinatra)
│   └── smtp-relay/                # SMTP Relay (Haraka)
│
├── config/                        # Конфигурации
│   ├── postal.yml.example         # Конфиг Postal
│   └── nginx.conf.example         # Конфиг Nginx
│
├── scripts/                       # Скрипты
│   ├── install.sh                 # Установщик
│   └── setup-local.sh             # Локальная настройка
│
├── docker-compose.yml             # Docker конфигурация
├── env.example.txt                # Пример переменных окружения
└── .gitignore                     # Игнорируемые файлы
```

## Быстрый старт

1. Прочитай `QUICK_START.md` — быстрый старт
2. Прочитай `docs/ARCHITECTURE.md` — понять систему
3. Прочитай `docs/DEPLOYMENT.md` — локальная установка
4. Прочитай `docs/API.md` — REST API спецификация
5. Начинай с `services/api/` — основной код

## История изменений

См. `CHANGELOG.md` для истории всех изменений, исправлений и новых функций.

## Запуск системы

### 1. Настройка окружения

```bash
# Скопировать пример конфигурации
cp env.example.txt .env

# Отредактировать .env и заполнить все секреты
# Генерация секретов:
openssl rand -hex 16  # для паролей БД
openssl rand -hex 32  # для SECRET_KEY_BASE, POSTAL_SIGNING_KEY, WEBHOOK_SECRET
openssl rand -hex 24  # для API_KEY
```

### 1.1. Генерация config/postal.yml из шаблона

Postal не поддерживает переменные окружения в YAML файле напрямую. Нужно сгенерировать `config/postal.yml` из шаблона:

**Вариант 1: Используя скрипт (Linux/Mac/Git Bash)**
```bash
bash scripts/generate-postal-config.sh
```

**Вариант 2: Вручную**
```bash
# Скопировать шаблон
cp config/postal.yml.example config/postal.yml

# Заменить переменные ${VAR} на реальные значения из .env
# Используйте любой текстовый редактор
```

**Вариант 3: Используя envsubst (если установлен)**
```bash
export $(grep -v '^#' .env | xargs)
envsubst < config/postal.yml.example > config/postal.yml
```

### 1.2. Создание файла htpasswd для Nginx Basic Auth

Файл `config/htpasswd` используется для базовой аутентификации в Nginx. Создайте его одним из способов:

**Вариант 1: Используя скрипт (Linux/Mac/Git Bash)**
```bash
bash scripts/create-htpasswd.sh admin admin123
```

**Вариант 2: Используя htpasswd (если установлен)**
```bash
htpasswd -bc config/htpasswd admin admin123
```

**Вариант 3: Используя Docker (если Docker запущен)**
```bash
docker run --rm -v "$PWD/config:/config" httpd:2.4-alpine htpasswd -b -c /config/htpasswd admin admin123
```

**Вариант 4: Используя openssl (если htpasswd недоступен)**
```bash
# Генерация хеша пароля
HASH=$(openssl passwd -apr1 admin123)
echo "admin:$HASH" > config/htpasswd
chmod 600 config/htpasswd
```

**Примечание:** Если файл `config/htpasswd` отсутствует, Nginx не сможет запуститься. По умолчанию создан пример файл с пользователем `admin` и паролем `admin123` (измените его для production!).

### 2. Запуск через Docker Compose

```bash
# Запустить все сервисы
docker compose up -d

# Просмотр логов
docker compose logs -f

# Проверка статуса
docker compose ps
```

### 3. Инициализация базы данных

```bash
# Выполнить миграции
docker compose exec api rails db:create db:migrate

# Создать API ключ для AMS
docker compose exec api rails runner "
  api_key, raw_key = ApiKey.generate(name: 'AMS Production')
  puts 'API Key: ' + raw_key
  puts 'Save this key - it will not be shown again!'
"
```

### 4. Смоук-тесты

```bash
# 1. Проверка health
curl http://localhost/api/v1/health

# 2. Отправка тестового письма через HTTP API (замените API_KEY на реальный ключ)
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "html_body": "<html><body><h1>Test Email</h1></body></html>",
    "from_name": "Test Sender",
    "from_email": "sender@example.com",
    "subject": "Test Email",
    "tracking": {
      "campaign_id": "test_camp",
      "message_id": "test_msg"
    }
  }'

# 3. Проверка статуса (замените test_msg на message_id из ответа)
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost/api/v1/status/test_msg

# 4. Проверка tracking (открытие)
curl "http://localhost/track/o?eid=$(echo -n 'test@example.com' | base64)&cid=$(echo -n 'test_camp' | base64)&mid=$(echo -n 'test_msg' | base64)"

# 5. Проверка tracking (клик)
curl "http://localhost/track/c?url=$(echo -n 'https://example.com' | base64)&eid=$(echo -n 'test@example.com' | base64)&cid=$(echo -n 'test_camp' | base64)&mid=$(echo -n 'test_msg' | base64)"
```

### 5. Проверка изоляции AMS

**Критически важно:** AMS не должен быть виден в письме!

```bash
# Проверить, что Message-ID генерируется на Send Server
# Формат должен быть: <local_{hex24}@send_server_domain>
# НЕ должен содержать "ams" или домены AMS

# Проверить заголовки письма (если есть доступ к логам Postal)
# Все заголовки должны быть от Send Server:
# - Message-ID: <local_...@send_server_domain>
# - Return-Path: bounce@send_server_domain
# - From: sender@allowed_domain (но отправка с Send Server)
```

## Структура проекта

После инициализации структура будет следующей:

```
services/api/
├── app/
│   ├── controllers/api/v1/    # API контроллеры
│   ├── models/                 # ActiveRecord модели
│   ├── jobs/                   # Sidekiq jobs
│   ├── services/               # Бизнес-логика
│   └── lib/                    # Утилиты (MessageIdGenerator)
├── config/                     # Конфигурация Rails
├── db/migrate/                 # Миграции БД
└── spec/                       # Тесты

services/tracking/
├── app.rb                      # Sinatra приложение
├── lib/                        # Обработчики трекинга
└── public/                     # Статические файлы (pixel.png)
```

## Технологии

| Компонент | Технология | Версия |
|-----------|------------|--------|
| API | Ruby on Rails | 7.1+ |
| Background Jobs | Sidekiq | 7.0+ |
| SMTP Relay | Haraka | latest |
| Database (API) | PostgreSQL | 15+ |
| Cache/Queue | Redis | 7.0+ |
| Mail Server | Postal | latest |
| Database (Postal) | MariaDB | 10.6+ |
| Message Broker | RabbitMQ | 3.12+ |
| Reverse Proxy | Nginx | 1.24+ |
| Containerization | Docker | 24+ |

## Критически важно

⚠️ **ПЕРЕД НАЧАЛОМ РАБОТЫ ОБЯЗАТЕЛЬНО ПРОЧИТАЙ:**

1. `docs/ARCHITECTURE.md` — без понимания архитектуры код будет неправильным
2. `docs/API_SPECIFICATION.md` — API должен быть ТОЧНО таким
3. `docs/SECURITY.md` — безопасность критична для email-систем

## Контакты

- Архитектор проекта: [описание в ARCHITECTURE.md]
- Вопросы: создавай issue в репозитории

