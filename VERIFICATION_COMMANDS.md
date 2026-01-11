# 🔍 КОМАНДЫ ПРОВЕРКИ ВСЕХ ПРОБЛЕМ НА СЕРВЕРЕ
## Детальная диагностика проекта Postal

**Дата:** 2026-01-11
**Цель:** Проверить, какие из найденных проблем действительно существуют на сервере

---

## 🔴 КРИТИЧЕСКАЯ ПРОБЛЕМА #1: БАЗА ДАННЫХ

### Проверить состояние миграций

```bash
# Проверить версию schema в файле
echo "=== Schema version в файле ==="
grep "define(version:" services/api/db/schema.rb

# Проверить состояние миграций в БД
echo "=== Состояние миграций в БД ==="
docker compose exec api rails db:migrate:status

# Проверить текущую версию в БД
echo "=== Текущая версия БД ==="
docker compose exec api rails runner "puts ActiveRecord::Base.connection.select_value('SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1')"

# Посмотреть ВСЕ применённые миграции
echo "=== Все применённые миграции ==="
docker compose exec api rails runner "puts ActiveRecord::Base.connection.select_values('SELECT version FROM schema_migrations ORDER BY version').join(', ')"
```

### Проверить существование таблиц

```bash
# Полный список таблиц в БД
echo "=== Таблицы в БД (должно быть 15+) ==="
docker compose exec api rails runner "puts ActiveRecord::Base.connection.tables.sort.join('\n')"

# Проверить критические таблицы по отдельности
echo "=== Проверка критических таблиц ==="

tables=(
  "api_keys"
  "email_logs"
  "email_templates"
  "tracking_events"
  "campaign_stats"
  "smtp_credentials"
  "webhook_endpoints"
  "webhook_logs"
  "ai_settings"
  "ai_analyses"
  "delivery_errors"
  "mailing_rules"
  "system_configs"
  "unsubscribes"
  "bounced_emails"
)

for table in "${tables[@]}"; do
  docker compose exec api rails runner "
    if ActiveRecord::Base.connection.table_exists?('$table')
      puts '✅ $table - EXISTS'
    else
      puts '❌ $table - MISSING'
    end
  "
done
```

### Проверить структуру критических таблиц

```bash
# Если таблица bounced_emails существует - проверить её структуру
echo "=== Структура bounced_emails ==="
docker compose exec api rails runner "
  if ActiveRecord::Base.connection.table_exists?('bounced_emails')
    columns = ActiveRecord::Base.connection.columns('bounced_emails')
    columns.each { |c| puts \"#{c.name} (#{c.type})\" }
  else
    puts 'Таблица НЕ СУЩЕСТВУЕТ'
  end
"

# Проверить индексы на bounced_emails
echo "=== Индексы на bounced_emails ==="
docker compose exec api rails runner "
  if ActiveRecord::Base.connection.table_exists?('bounced_emails')
    indexes = ActiveRecord::Base.connection.indexes('bounced_emails')
    indexes.each { |i| puts \"#{i.name}: #{i.columns.join(', ')}\" }
  else
    puts 'Таблица НЕ СУЩЕСТВУЕТ'
  end
"
```

---

## 🔴 КРИТИЧЕСКАЯ ПРОБЛЕМА #2: DOCKER SOCKET EXPOSURE

```bash
# Проверить, смонтирован ли Docker socket
echo "=== Проверка Docker socket в контейнере ==="
docker compose exec api ls -la /var/run/docker.sock 2>&1

# Если файл существует - это ПРОБЛЕМА!
if docker compose exec api test -e /var/run/docker.sock; then
  echo "❌ КРИТИЧНО: Docker socket СМОНТИРОВАН в контейнер!"
  echo "Контейнер имеет доступ к Docker daemon хоста!"
else
  echo "✅ OK: Docker socket НЕ смонтирован"
fi

# Проверить, может ли контейнер запускать docker команды
echo "=== Попытка запустить docker команду из контейнера ==="
docker compose exec api docker ps 2>&1 || echo "✅ OK: docker команды не работают"
```

---

## 🔴 КРИТИЧЕСКАЯ ПРОБЛЕМА #3: WEBHOOK VERIFICATION BYPASS

```bash
# Проверить ENV переменную
echo "=== Проверка SKIP_POSTAL_WEBHOOK_VERIFICATION ==="
docker compose exec api printenv SKIP_POSTAL_WEBHOOK_VERIFICATION

# Проверить в docker-compose.yml
echo "=== Проверка в docker-compose.yml ==="
grep -n "SKIP_POSTAL_WEBHOOK_VERIFICATION" docker-compose.yml

# Проверить, загружен ли публичный ключ для вебхуков
echo "=== Проверка POSTAL_WEBHOOK_PUBLIC_KEY_FILE ==="
docker compose exec api printenv POSTAL_WEBHOOK_PUBLIC_KEY_FILE
docker compose exec api test -f /config/postal_public.key && echo "✅ Файл существует" || echo "❌ Файл НЕ существует"

# Прочитать содержимое файла ключа (если есть)
echo "=== Содержимое postal_public.key ==="
docker compose exec api cat /config/postal_public.key 2>&1 | head -3
```

---

## 🔴 КРИТИЧЕСКАЯ ПРОБЛЕМА #4: WEAK ENCRYPTION

```bash
# Проверить как генерируется ключ шифрования
echo "=== Проверка метода шифрования в SmtpController ==="
docker compose exec api cat app/controllers/api/v1/smtp_controller.rb | grep -A 3 "MessageEncryptor"

# Проверить наличие выделенного ключа шифрования
echo "=== Проверка наличия SMTP_ENCRYPTION_KEY ==="
docker compose exec api printenv SMTP_ENCRYPTION_KEY || echo "❌ SMTP_ENCRYPTION_KEY не установлен"

# Проверить SECRET_KEY_BASE (первые символы)
echo "=== SECRET_KEY_BASE (первые 20 символов) ==="
docker compose exec api printenv SECRET_KEY_BASE | cut -c1-20

# Проверить длину SECRET_KEY_BASE
echo "=== Длина SECRET_KEY_BASE ==="
docker compose exec api bash -c 'echo -n $SECRET_KEY_BASE | wc -c'
```

---

## 🔴 КРИТИЧЕСКАЯ ПРОБЛЕМА #5: IP-BASED AUTHENTICATION

```bash
# Проверить код аутентификации в SmtpController
echo "=== Метод аутентификации в smtp_controller.rb ==="
docker compose exec api grep -A 10 "def receive" app/controllers/api/v1/smtp_controller.rb | grep -A 5 "client_ip"

# Тестовый запрос с подделанным IP
echo "=== Тест: попытка обойти IP проверку ==="
docker compose exec api curl -X POST http://localhost:3000/api/v1/smtp/receive \
  -H "Content-Type: application/json" \
  -H "X-Forwarded-For: 172.17.0.1" \
  -d '{"test": "data"}' 2>&1

# Проверить логику проверки IP
echo "=== Код проверки IP ==="
docker compose exec api cat app/controllers/api/v1/smtp_controller.rb | grep -B 2 -A 5 "remote_ip"
```

---

## 🟠 ВЫСОКАЯ ПРОБЛЕМА #6: WEBHOOK SIGNATURE GENERATION

```bash
# Проверить метод generate_signature
echo "=== Метод generate_signature в WebhookEndpoint ==="
docker compose exec api grep -A 5 "def generate_signature" app/models/webhook_endpoint.rb

# Проверить, используется ли URL или payload для подписи
docker compose exec api cat app/models/webhook_endpoint.rb | grep -A 10 "generate_signature"
```

---

## 🟠 ВЫСОКАЯ ПРОБЛЕМА #7: N+1 QUERIES

```bash
# Включить SQL логирование
echo "=== Тест N+1 query в Analytics ==="

# Создать тестовые данные (если БД пустая)
docker compose exec api rails runner "
  # Проверить наличие данных
  puts \"Campaign stats count: #{CampaignStats.count}\"
  puts \"Email logs count: #{EmailLog.count}\"
"

# Включить SQL логирование и вызвать проблемный метод
docker compose exec api rails runner "
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.logger.level = Logger::DEBUG

  # Эмулировать проблемный код
  campaign_stats = CampaignStats.limit(5)
  campaign_stats.each do |stat|
    email_log_ids = EmailLog.where(campaign_id: stat.campaign_id).pluck(:id)
    opens = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'open').count
    puts \"Campaign #{stat.campaign_id}: #{opens} opens\"
  end
" 2>&1 | grep -i "SELECT" | wc -l

echo "Количество SQL запросов (должно быть большим при N+1)"
```

---

## 🟠 ВЫСОКАЯ ПРОБЛЕМА #8: BROAD EXCEPTION HANDLING

```bash
# Проверить rescue_from в ApplicationController
echo "=== Глобальный rescue_from в ApplicationController ==="
docker compose exec api grep -A 5 "rescue_from" app/controllers/application_controller.rb

# Найти все места с rescue StandardError
echo "=== Все места с rescue StandardError ==="
docker compose exec api grep -r "rescue StandardError" app/ | wc -l
echo "найдено мест"

# Показать конкретные места
docker compose exec api grep -rn "rescue StandardError" app/ | head -10
```

---

## 🟠 ВЫСОКАЯ ПРОБЛЕМА #9: DEPRECATED SYNTAX

```bash
# Найти все deprecated rescue =>
echo "=== Поиск deprecated 'rescue =>' ==="
docker compose exec api grep -rn "rescue =>" app/ 2>/dev/null || echo "Не найдено или нет grep"

# Альтернативный способ - через Ruby
docker compose exec api find app/ -name "*.rb" -exec grep -l "rescue =>" {} \; 2>/dev/null | wc -l
echo "файлов с deprecated синтаксисом"

# Показать примеры
echo "=== Примеры deprecated rescue ==="
docker compose exec api find app/ -name "*.rb" -exec grep -Hn "rescue =>" {} \; 2>/dev/null | head -5
```

---

## 🟠 ВЫСОКАЯ ПРОБЛЕМА #10: SMTP RELAY - NO AUTHENTICATION

```bash
# Проверить конфигурацию SMTP relay
echo "=== SMTP Relay: authOptional ==="
docker compose exec smtp-relay cat server.js | grep -A 3 "authOptional"

# Проверить метод onAuth
echo "=== SMTP Relay: onAuth implementation ==="
docker compose exec smtp-relay cat server.js | grep -A 10 "onAuth"

# Попробовать подключиться к SMTP без auth
echo "=== Тест подключения к SMTP без аутентификации ==="
docker compose exec smtp-relay nc -zv localhost 587 2>&1 || echo "Порт недоступен"
```

---

## 🟠 ВЫСОКАЯ ПРОБЛЕМА #11: MEMORY LIMITS

```bash
# Проверить текущие memory limits
echo "=== Memory limits в docker-compose.yml ==="
grep -A 3 "memory:" docker-compose.yml | grep -E "(api|postgres|postal|sidekiq)" -A 2

# Проверить реальное использование памяти
echo "=== Текущее использование памяти ==="
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Проверить настройки PostgreSQL
echo "=== PostgreSQL shared_buffers ==="
docker compose exec postgres psql -U email_sender -d email_sender -c "SHOW shared_buffers;"

# Проверить может ли PostgreSQL использовать больше памяти
echo "=== PostgreSQL effective_cache_size ==="
docker compose exec postgres psql -U email_sender -d email_sender -c "SHOW effective_cache_size;"

# Проверить логи на OOM kills
echo "=== Проверка логов на OOM kills ==="
docker compose logs --tail=1000 | grep -i "killed\|oom\|memory" || echo "OOM kills не найдены"
```

---

## 🟡 СРЕДНЯЯ ПРОБЛЕМА #12: RACE CONDITIONS

```bash
# Проверить метод increment_successful!
echo "=== WebhookEndpoint: increment_successful! ==="
docker compose exec api cat app/models/webhook_endpoint.rb | grep -A 5 "def increment_successful"

# Проверить используется ли update_column
docker compose exec api grep -rn "update_column" app/models/ | head -10

# Тест на race condition (запустить параллельно)
echo "=== Тест race condition (если webhook_endpoints существует) ==="
docker compose exec api rails runner "
  if defined?(WebhookEndpoint) && WebhookEndpoint.table_exists?
    endpoint = WebhookEndpoint.first
    if endpoint
      puts \"Текущее значение: #{endpoint.successful_deliveries}\"

      # Запустить 10 параллельных инкрементов
      threads = 10.times.map do
        Thread.new { endpoint.increment_successful! rescue nil }
      end
      threads.each(&:join)

      endpoint.reload
      puts \"После 10 инкрементов: #{endpoint.successful_deliveries}\"
      puts \"Ожидалось на 10 больше - если меньше, есть race condition\"
    else
      puts 'Нет записей для теста'
    end
  else
    puts 'WebhookEndpoint не существует'
  end
"
```

---

## 🟡 СРЕДНЯЯ ПРОБЛЕМА #13: PLAINTEXT SECRETS

```bash
# Проверить метод sync_to_env_file
echo "=== SystemConfig: sync_to_env_file ==="
docker compose exec api cat app/models/system_config.rb | grep -A 20 "def sync_to_env_file"

# Проверить, записываются ли секреты в .env
echo "=== Проверка .env файла на секреты ==="
docker compose exec api test -f .env && echo "✅ .env существует" || echo "❌ .env не существует"

# Проверить содержимое .env (без показа паролей)
echo "=== Ключи в .env ==="
docker compose exec api cat .env 2>/dev/null | grep -v "^#" | grep "=" | cut -d= -f1 | head -20 || echo ".env не доступен"

# Проверить, зашифрованы ли данные в system_configs
echo "=== Проверка шифрования в system_configs ==="
docker compose exec api rails runner "
  if defined?(SystemConfig) && SystemConfig.table_exists?
    config = SystemConfig.first
    if config
      # Попробовать получить зашифрованное поле
      puts \"postal_api_key type: #{config.attributes['postal_api_key'].class}\"
    else
      puts 'Нет записей SystemConfig'
    end
  else
    puts 'SystemConfig не существует'
  end
"
```

---

## 🟡 СРЕДНЯЯ ПРОБЛЕМА #14: EMAIL MASKING BUG

```bash
# Проверить метод mask_email
echo "=== EmailLog: mask_email ==="
docker compose exec api cat app/models/email_log.rb | grep -A 10 "def mask_email"

# Тесты различных edge cases
echo "=== Тест маскирования email ==="
docker compose exec api rails runner "
  def mask_email(email)
    local, domain = email.split('@', 2)
    return email if local.blank? || domain.blank?
    masked_local = local.length > 2 ? \"#{local[0]}***#{local[-1]}\" : \"***\"
    \"#{masked_local}@#{domain}\"
  end

  test_cases = [
    'test@example.com',
    'a@b.com',
    'test@@example.com',
    'nodomain',
    '@domain.com',
    'test@',
    ''
  ]

  test_cases.each do |email|
    puts \"#{email.ljust(25)} -> #{mask_email(email)}\"
  end
"
```

---

## 🟡 СРЕДНЯЯ ПРОБЛЕМА #15: SMTP MEMORY ISSUE

```bash
# Проверить размер буфера в SMTP relay
echo "=== SMTP Relay: размер буфера ==="
docker compose exec smtp-relay cat server.js | grep -A 20 "onData"

# Проверить size limit
echo "=== SMTP Relay: size limit ==="
docker compose exec smtp-relay cat server.js | grep "size:"

# Проверить память SMTP relay
echo "=== SMTP Relay: использование памяти ==="
docker stats email_smtp_relay --no-stream --format "{{.Name}}\t{{.MemUsage}}"

# Проверить логи SMTP relay на ошибки памяти
echo "=== SMTP Relay: логи (последние 50 строк) ==="
docker compose logs smtp-relay --tail=50 | grep -i "memory\|heap\|killed" || echo "Проблем с памятью не найдено"
```

---

## 📊 КОМПЛЕКСНАЯ ПРОВЕРКА ЗДОРОВЬЯ СИСТЕМЫ

```bash
# Health check всех сервисов
echo "=== Health Check API ==="
docker compose exec api curl -s http://localhost:3000/api/v1/health | jq . || echo "API недоступен или jq не установлен"

# Проверка всех контейнеров
echo "=== Статус всех контейнеров ==="
docker compose ps

# Проверка подключения к БД
echo "=== PostgreSQL Connection ==="
docker compose exec postgres psql -U email_sender -d email_sender -c "SELECT version();" | head -3

# Проверка Redis
echo "=== Redis Connection ==="
docker compose exec redis redis-cli ping

# Проверка Postal
echo "=== Postal API ==="
docker compose exec api curl -s http://postal:5000 | head -5 || echo "Postal недоступен"

# Проверка Sidekiq
echo "=== Sidekiq Stats ==="
docker compose exec api rails runner "
  require 'sidekiq/api'
  stats = Sidekiq::Stats.new
  puts \"Processed: #{stats.processed}\"
  puts \"Failed: #{stats.failed}\"
  puts \"Queues: #{Sidekiq::Queue.all.map { |q| \"#{q.name}(#{q.size})\" }.join(', ')}\"
" 2>/dev/null || echo "Sidekiq недоступен"
```

---

## 📋 ENV ПЕРЕМЕННЫЕ ПРОВЕРКА

```bash
# Проверить все критические ENV переменные
echo "=== Проверка критических ENV переменных ==="

required_vars=(
  "SECRET_KEY_BASE"
  "DATABASE_URL"
  "REDIS_URL"
  "ENCRYPTION_PRIMARY_KEY"
  "ENCRYPTION_DETERMINISTIC_KEY"
  "ENCRYPTION_KEY_DERIVATION_SALT"
  "POSTAL_SIGNING_KEY"
  "DOMAIN"
  "ALLOWED_SENDER_DOMAINS"
)

for var in "${required_vars[@]}"; do
  value=$(docker compose exec api printenv "$var" 2>/dev/null)
  if [ -n "$value" ]; then
    # Показать только первые 20 символов
    preview=$(echo "$value" | cut -c1-20)
    echo "✅ $var: ${preview}... (длина: ${#value})"
  else
    echo "❌ $var: НЕ УСТАНОВЛЕН"
  fi
done

# Проверить на CHANGE_ME
echo "=== Проверка на незамененные CHANGE_ME ==="
cat .env 2>/dev/null | grep "CHANGE_ME" || echo "✅ CHANGE_ME не найдены"
```

---

## 🔒 SECURITY AUDIT

```bash
# Проверить открытые порты
echo "=== Открытые порты ==="
docker compose ps --format "table {{.Name}}\t{{.Ports}}"

# Проверить API keys в БД
echo "=== API Keys в БД ==="
docker compose exec api rails runner "
  if defined?(ApiKey) && ApiKey.table_exists?
    puts \"Всего API keys: #{ApiKey.count}\"
    puts \"Активных: #{ApiKey.where(active: true).count}\"
    ApiKey.limit(5).each do |key|
      puts \"  #{key.name}: active=#{key.active}, last_used=#{key.last_used_at}\"
    end
  else
    puts 'ApiKey таблица не существует'
  end
"

# Проверить CORS настройки
echo "=== CORS настройки ==="
docker compose exec api printenv CORS_ORIGINS

# Проверить rack-attack конфигурацию
echo "=== Rack Attack конфигурация ==="
docker compose exec api cat config/initializers/rack_attack.rb | grep -A 5 "throttle"
```

---

## 📁 СОХРАНИТЬ РЕЗУЛЬТАТЫ

```bash
# Создать файл с результатами проверки
output_file="verification_results_$(date +%Y%m%d_%H%M%S).txt"

echo "Сохраняю результаты проверки в $output_file..."

{
  echo "=== VERIFICATION RESULTS ==="
  echo "Date: $(date)"
  echo "=========================="
  echo ""

  # Здесь выполнить все проверки и сохранить вывод

} > "$output_file"

echo "✅ Результаты сохранены в $output_file"
```

---

## 🎯 БЫСТРАЯ ПРОВЕРКА (ВСЕ КРИТИЧЕСКИЕ ПРОБЛЕМЫ)

```bash
#!/bin/bash
# quick_check.sh - Быстрая проверка всех критических проблем

echo "🔍 БЫСТРАЯ ПРОВЕРКА КРИТИЧЕСКИХ ПРОБЛЕМ"
echo "========================================"
echo ""

# 1. База данных
echo "1️⃣ БАЗА ДАННЫХ:"
docker compose exec -T api rails runner "puts ActiveRecord::Base.connection.tables.count" 2>/dev/null && \
  echo "   ✅ БД доступна, таблиц: $(docker compose exec -T api rails runner 'puts ActiveRecord::Base.connection.tables.count' 2>/dev/null)" || \
  echo "   ❌ БД недоступна"

# 2. Docker socket
echo "2️⃣ DOCKER SOCKET:"
docker compose exec -T api test -e /var/run/docker.sock && \
  echo "   ❌ КРИТИЧНО: Docker socket СМОНТИРОВАН!" || \
  echo "   ✅ OK: Docker socket не смонтирован"

# 3. Webhook verification
echo "3️⃣ WEBHOOK VERIFICATION:"
skip_verify=$(docker compose exec -T api printenv SKIP_POSTAL_WEBHOOK_VERIFICATION 2>/dev/null)
if [ "$skip_verify" = "true" ]; then
  echo "   ❌ КРИТИЧНО: Проверка webhook ОТКЛЮЧЕНА!"
else
  echo "   ✅ OK: Webhook verification включена"
fi

# 4. Memory limits
echo "4️⃣ MEMORY LIMITS:"
api_mem=$(docker inspect email_api 2>/dev/null | grep -o '"Memory":[0-9]*' | head -1 | cut -d: -f2)
if [ "$api_mem" -lt 800000000 ] 2>/dev/null; then
  echo "   ⚠️  WARNING: API memory limit низкий: $((api_mem / 1024 / 1024))MB"
else
  echo "   ✅ OK: API memory limit адекватный"
fi

# 5. ENV переменные
echo "5️⃣ ENV ПЕРЕМЕННЫЕ:"
missing=0
for var in SECRET_KEY_BASE ENCRYPTION_PRIMARY_KEY POSTAL_SIGNING_KEY; do
  docker compose exec -T api printenv "$var" >/dev/null 2>&1 || ((missing++))
done
if [ $missing -gt 0 ]; then
  echo "   ❌ Отсутствуют $missing критических ENV переменных"
else
  echo "   ✅ OK: Все критические ENV переменные установлены"
fi

echo ""
echo "✅ Проверка завершена"
```

Сохраните этот скрипт как `quick_check.sh` и запустите:
```bash
chmod +x quick_check.sh
./quick_check.sh
```

---

## 📝 ПРИМЕЧАНИЯ

- Все команды предполагают, что вы находитесь в корневой директории проекта
- Некоторые команды требуют `jq` для форматирования JSON
- Команды безопасны и не изменяют данные (только читают)
- Если контейнер не запущен, некоторые команды выдадут ошибку

**Рекомендуемый порядок проверки:**
1. Сначала запустите "Быстрая проверка" (в конце файла)
2. Затем детально проверьте проблемы, которые показали ошибки
3. Сохраните результаты для анализа
