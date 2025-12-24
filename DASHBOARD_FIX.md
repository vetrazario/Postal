# ИСПРАВЛЕНИЕ DASHBOARD (ПАНЕЛИ УПРАВЛЕНИЯ)

## 🔴 Критическая проблема

### Dashboard не открывается - ошибка 500 или требует пароль ❌

**Обнаружено в `dashboard_controller.rb` (строки 6-9):**
```ruby
http_basic_authenticate_with(
  name: ENV.fetch("DASHBOARD_USERNAME"),
  password: ENV.fetch("DASHBOARD_PASSWORD")
)
```

**Проблемы:**

1. **ENV.fetch() падает с ошибкой если переменная не задана**
   - Если `DASHBOARD_USERNAME` или `DASHBOARD_PASSWORD` не установлены в `.env`
   - Rails выдает ошибку 500 (KeyError: key not found)
   - Dashboard вообще не открывается

2. **HTTP Basic Authentication не настроен**
   - Даже если переменные заданы, браузер требует логин/пароль
   - Пользователь не знает какие учетные данные вводить

3. **Пароль по умолчанию - заглушка**
   - В `env.example.txt`: `DASHBOARD_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD`
   - Если пользователь не изменил - пароль слишком длинный и непонятный

---

## ✅ БЫСТРОЕ ИСПРАВЛЕНИЕ

### Шаг 1: Установите учетные данные в .env

```bash
cd /home/user/Postal

# Откройте .env
nano .env

# Найдите и установите (если не заданы):
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=ваш_безопасный_пароль

# Сохраните: Ctrl+O, Enter, Ctrl+X
```

**Или автоматически сгенерируйте:**

```bash
# Генерация случайного пароля
DASH_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Добавление в .env (если еще нет)
if ! grep -q "DASHBOARD_USERNAME" .env; then
    echo "DASHBOARD_USERNAME=admin" >> .env
fi

if ! grep -q "DASHBOARD_PASSWORD" .env; then
    echo "DASHBOARD_PASSWORD=$DASH_PASS" >> .env
else
    # Заменить существующий
    sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASH_PASS/" .env
fi

echo "Dashboard credentials:"
echo "  Username: admin"
echo "  Password: $DASH_PASS"
echo ""
echo "⚠️  СОХРАНИТЕ ЭТИ ДАННЫЕ!"
```

### Шаг 2: Перезапустите Rails API

```bash
docker compose restart api sidekiq

# Подождите запуска
sleep 10
```

### Шаг 3: Откройте Dashboard

Откройте в браузере: **http://your-server-ip/dashboard**

Браузер попросит ввести:
- **Username:** admin (или что вы установили в DASHBOARD_USERNAME)
- **Password:** ваш пароль из DASHBOARD_PASSWORD

---

## 📋 ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ

### Проверка 1: Установлены ли переменные?

```bash
cd /home/user/Postal

# Проверьте .env
grep -E "DASHBOARD_USERNAME|DASHBOARD_PASSWORD" .env

# Должно быть:
# DASHBOARD_USERNAME=admin
# DASHBOARD_PASSWORD=какой-то_пароль

# Если пусто или нет - значит не установлено!
```

### Проверка 2: Передаются ли переменные в контейнер?

```bash
# Проверьте что переменные попадают в контейнер
docker compose exec api env | grep DASHBOARD

# Должно вывести:
# DASHBOARD_USERNAME=admin
# DASHBOARD_PASSWORD=ваш_пароль

# Если пусто - переменные не установлены в .env
```

### Проверка 3: Работает ли Rails API?

```bash
# Проверьте логи на ошибки
docker compose logs api --tail=50 | grep -i "dashboard\|error"

# Ищите:
# - "KeyError: key not found: DASHBOARD_USERNAME" → переменные не заданы
# - "401 Unauthorized" → неверный пароль
# - "200 OK /dashboard" → всё работает!
```

### Проверка 4: Доступен ли Dashboard через nginx?

```bash
# Попробуйте запрос с базовой аутентификацией
curl -u admin:ваш_пароль http://localhost/dashboard

# Должно вернуть HTML страницу
# Если 401 - неверный пароль
# Если 500 - переменные не заданы
# Если 200 - всё работает!
```

---

## 🔧 ИСПРАВЛЕНИЕ КОДА (для разработчиков)

Проблема в том, что `ENV.fetch()` бросает исключение если переменная не задана.

### Текущий код (НЕПРАВИЛЬНО):
```ruby
# dashboard_controller.rb
http_basic_authenticate_with(
  name: ENV.fetch("DASHBOARD_USERNAME"),
  password: ENV.fetch("DASHBOARD_PASSWORD")
)
```

### Правильный код (БЕЗОПАСНЫЙ):
```ruby
# dashboard_controller.rb
if ENV["DASHBOARD_USERNAME"].present? && ENV["DASHBOARD_PASSWORD"].present?
  http_basic_authenticate_with(
    name: ENV.fetch("DASHBOARD_USERNAME"),
    password: ENV.fetch("DASHBOARD_PASSWORD")
  )
else
  before_action :require_no_auth_warning

  def require_no_auth_warning
    Rails.logger.warn("Dashboard accessed without authentication! Set DASHBOARD_USERNAME and DASHBOARD_PASSWORD")
  end
end
```

Или еще лучше - использовать значения по умолчанию:
```ruby
# dashboard_controller.rb
http_basic_authenticate_with(
  name: ENV.fetch("DASHBOARD_USERNAME", "admin"),
  password: ENV.fetch("DASHBOARD_PASSWORD", "changeme")
)
```

**НО** это небезопасно для production! Лучше требовать обязательной установки учетных данных.

---

## 📊 ЧТО ПОКАЗЫВАЕТ DASHBOARD?

После успешного входа вы увидите:

### Главная страница (/dashboard)
- **Статистика за период:** сегодня, вчера, неделя, месяц
- **Метрики:**
  - Всего отправлено
  - Доставлено
  - Bounced (отскоки)
  - Failed (неудачи)
  - Opened (открытия)
  - Clicked (клики)
  - Complained (жалобы на спам)
- **Показатели:**
  - Delivery rate (процент доставки)
  - Bounce rate (процент отскоков)
  - Open rate (процент открытий)
  - Click rate (процент кликов)
  - Complaint rate (процент жалоб)
- **Последние 50 писем** с информацией:
  - Время отправки
  - Получатель (замаскирован)
  - Статус
  - ID кампании
  - Количество открытий
  - Количество кликов

### Страница логов (/dashboard/logs)
- **Фильтры:**
  - По статусу (delivered, bounced, failed, etc.)
  - По campaign_id
  - По периоду
- **Пагинация:** 50 записей на страницу
- **Детали каждого письма:**
  - Полная информация о доставке
  - События трекинга (открытия, клики)
  - Временные метки

---

## 🛠️ ЧАСТЫЕ ОШИБКИ

### Ошибка: "Internal Server Error" (500)

**Причина:** Переменные DASHBOARD_USERNAME или DASHBOARD_PASSWORD не заданы

**Решение:**
```bash
# 1. Проверьте .env
grep DASHBOARD .env

# 2. Если нет - добавьте
echo "DASHBOARD_USERNAME=admin" >> .env
echo "DASHBOARD_PASSWORD=$(openssl rand -base64 16)" >> .env

# 3. Перезапустите
docker compose restart api
```

### Ошибка: Браузер требует логин/пароль, но они не работают

**Причина:** Пароль в .env не совпадает с тем что вы вводите

**Решение:**
```bash
# Посмотрите текущий пароль
grep DASHBOARD_PASSWORD .env

# Используйте этот пароль, или измените на новый:
nano .env
# Найдите DASHBOARD_PASSWORD и измените
# Сохраните и перезапустите:
docker compose restart api
```

### Ошибка: 404 Not Found на /dashboard

**Причина:** Nginx или Rails API не работают

**Решение:**
```bash
# Проверьте что API запущен
docker compose ps api

# Проверьте логи
docker compose logs api --tail=50

# Проверьте nginx конфигурацию
grep "location /dashboard" config/nginx.conf

# Должно быть:
# location /dashboard {
#     proxy_pass http://api_backend;
#     ...
# }
```

### Ошибка: Dashboard открывается но пустой (нет данных)

**Причина:** Письма еще не отправлялись или база данных пустая

**Решение:**
```bash
# Проверьте что БД инициализирована
docker compose exec api rails db:migrate

# Отправьте тестовое письмо через API
curl -X POST http://localhost/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "html_body": "<h1>Test</h1>",
    "from_email": "sender@yourdomain.com",
    "subject": "Test"
  }'

# Обновите Dashboard - должны появиться данные
```

---

## 🔒 БЕЗОПАСНОСТЬ

### Рекомендации для Production:

1. **Используйте сложный пароль:**
   ```bash
   # Минимум 16 символов, случайный
   openssl rand -base64 24
   ```

2. **Ограничьте доступ к Dashboard через firewall:**
   ```bash
   # Разрешите доступ только с определенных IP
   # Настройте в nginx.conf:
   location /dashboard {
       allow 192.168.1.0/24;  # ваша внутренняя сеть
       deny all;

       proxy_pass http://api_backend;
       # ...
   }
   ```

3. **Используйте HTTPS:**
   ```bash
   # Настройте Let's Encrypt SSL
   docker compose run --rm certbot certbot certonly ...
   ```

4. **Регулярно меняйте пароль:**
   ```bash
   # Раз в 3 месяца генерируйте новый
   NEW_PASS=$(openssl rand -base64 24)
   sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$NEW_PASS/" .env
   docker compose restart api
   echo "New password: $NEW_PASS"
   ```

5. **Включите двухфакторную аутентификацию** (для продвинутых):
   - Рассмотрите использование OAuth2 / OIDC
   - Или VPN для доступа к Dashboard

---

## 📝 АВТОМАТИЗАЦИЯ

### Скрипт для быстрой настройки Dashboard:

```bash
#!/bin/bash
# setup-dashboard.sh

cd /home/user/Postal

# Проверка .env
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "Run: sudo bash scripts/pre-install.sh"
    exit 1
fi

# Генерация учетных данных если их нет
if ! grep -q "DASHBOARD_USERNAME" .env || ! grep -q "DASHBOARD_PASSWORD" .env; then
    echo "🔧 Generating Dashboard credentials..."

    USERNAME="admin"
    PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

    # Добавить или обновить
    if grep -q "DASHBOARD_USERNAME" .env; then
        sed -i "s/^DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$USERNAME/" .env
    else
        echo "DASHBOARD_USERNAME=$USERNAME" >> .env
    fi

    if grep -q "DASHBOARD_PASSWORD" .env; then
        sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$PASSWORD/" .env
    else
        echo "DASHBOARD_PASSWORD=$PASSWORD" >> .env
    fi

    echo "✅ Dashboard credentials generated:"
    echo "   Username: $USERNAME"
    echo "   Password: $PASSWORD"
    echo ""
    echo "⚠️  SAVE THESE CREDENTIALS!"
    echo ""
else
    echo "✅ Dashboard credentials already set in .env"
    USERNAME=$(grep DASHBOARD_USERNAME .env | cut -d= -f2)
    PASSWORD=$(grep DASHBOARD_PASSWORD .env | cut -d= -f2)
    echo "   Username: $USERNAME"
    echo "   Password: $PASSWORD"
    echo ""
fi

# Перезапуск API
echo "🔄 Restarting API..."
docker compose restart api sidekiq

echo ""
echo "✅ Dashboard is ready!"
echo ""
echo "Access at: http://your-server-ip/dashboard"
echo "Login with the credentials above"
echo ""
```

Сохраните как `scripts/setup-dashboard.sh` и запустите:
```bash
chmod +x scripts/setup-dashboard.sh
sudo bash scripts/setup-dashboard.sh
```

---

## ✅ ПРОВЕРКА ПОСЛЕ НАСТРОЙКИ

```bash
# 1. Проверьте что переменные установлены
grep DASHBOARD .env

# 2. Проверьте что они в контейнере
docker compose exec api env | grep DASHBOARD

# 3. Попробуйте доступ через curl
curl -u admin:ваш_пароль http://localhost/dashboard

# 4. Откройте в браузере
# http://your-server-ip/dashboard
# Введите логин и пароль

# 5. Должны увидеть Dashboard с метриками
```

---

**Готово!** После этих шагов Dashboard будет полностью работать. 🎉
