#!/bin/bash
# Detailed Check Script - Детальная проверка с сохранением результатов
# Использование: ./detailed_check.sh

set -e

OUTPUT_FILE="verification_results_$(date +%Y%m%d_%H%M%S).txt"

echo "🔍 ДЕТАЛЬНАЯ ПРОВЕРКА ПРОЕКТА POSTAL"
echo "Результаты будут сохранены в: $OUTPUT_FILE"
echo ""

# Функция для логирования
log() {
  echo "$@" | tee -a "$OUTPUT_FILE"
}

log_section() {
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "$@"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
}

# Начало отчета
{
  echo "VERIFICATION RESULTS"
  echo "===================="
  echo "Date: $(date)"
  echo "Host: $(hostname)"
  echo "===================="
  echo ""
} > "$OUTPUT_FILE"

log_section "1. ИНФОРМАЦИЯ О СИСТЕМЕ"

log "Docker версия:"
docker --version | tee -a "$OUTPUT_FILE"

log ""
log "Docker Compose версия:"
docker compose version | tee -a "$OUTPUT_FILE"

log ""
log "Статус контейнеров:"
docker compose ps | tee -a "$OUTPUT_FILE"

log_section "2. ПРОВЕРКА БАЗЫ ДАННЫХ"

log "Подключение к PostgreSQL:"
docker compose exec -T postgres psql -U email_sender -d email_sender -c "SELECT version();" 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Список таблиц в БД:"
docker compose exec -T api rails runner "puts ActiveRecord::Base.connection.tables.sort.join('\n')" 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Количество таблиц:"
docker compose exec -T api rails runner "puts ActiveRecord::Base.connection.tables.count" 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Статус миграций:"
docker compose exec -T api rails db:migrate:status 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Проверка критических таблиц:"
for table in api_keys email_logs email_templates tracking_events campaign_stats smtp_credentials webhook_endpoints webhook_logs ai_settings ai_analyses delivery_errors mailing_rules system_configs unsubscribes bounced_emails; do
  exists=$(docker compose exec -T api rails runner "puts ActiveRecord::Base.connection.table_exists?('$table')" 2>/dev/null || echo "ERROR")
  log "  $table: $exists"
done

log_section "3. ПРОВЕРКА БЕЗОПАСНОСТИ"

log "Docker Socket Exposure:"
if docker compose exec -T api test -e /var/run/docker.sock 2>/dev/null; then
  log "  ❌ КРИТИЧНО: /var/run/docker.sock СУЩЕСТВУЕТ в контейнере!"
  log "  Содержимое:"
  docker compose exec -T api ls -la /var/run/docker.sock 2>&1 | tee -a "$OUTPUT_FILE"
else
  log "  ✅ OK: Docker socket не смонтирован"
fi

log ""
log "Webhook Verification:"
skip_verify=$(docker compose exec -T api printenv SKIP_POSTAL_WEBHOOK_VERIFICATION 2>/dev/null || echo "not_set")
log "  SKIP_POSTAL_WEBHOOK_VERIFICATION=$skip_verify"

if [ "$skip_verify" = "true" ]; then
  log "  ❌ КРИТИЧНО: Проверка подписи ОТКЛЮЧЕНА!"
else
  log "  ✅ OK: Verification включена"
fi

log ""
log "Публичный ключ Postal:"
pubkey_file=$(docker compose exec -T api printenv POSTAL_WEBHOOK_PUBLIC_KEY_FILE 2>/dev/null || echo "not_set")
log "  POSTAL_WEBHOOK_PUBLIC_KEY_FILE=$pubkey_file"

if [ "$pubkey_file" != "not_set" ]; then
  if docker compose exec -T api test -f "$pubkey_file" 2>/dev/null; then
    log "  ✅ Файл существует"
    log "  Первые строки:"
    docker compose exec -T api head -3 "$pubkey_file" 2>&1 | tee -a "$OUTPUT_FILE"
  else
    log "  ❌ Файл НЕ существует"
  fi
fi

log_section "4. ENV ПЕРЕМЕННЫЕ"

log "Критические переменные:"
for var in SECRET_KEY_BASE DATABASE_URL REDIS_URL ENCRYPTION_PRIMARY_KEY ENCRYPTION_DETERMINISTIC_KEY ENCRYPTION_KEY_DERIVATION_SALT POSTAL_SIGNING_KEY DOMAIN ALLOWED_SENDER_DOMAINS; do
  value=$(docker compose exec -T api printenv "$var" 2>/dev/null || echo "NOT_SET")
  if [ "$value" = "NOT_SET" ]; then
    log "  ❌ $var: НЕ УСТАНОВЛЕН"
  else
    # Показать только длину и первые символы
    len=${#value}
    preview=$(echo "$value" | cut -c1-20)
    log "  ✅ $var: установлен (длина: $len, начало: ${preview}...)"
  fi
done

log ""
log "Проверка на CHANGE_ME:"
change_me_count=$(docker compose exec -T api cat .env 2>/dev/null | grep -c "CHANGE_ME" || echo "0")
if [ "$change_me_count" -gt 0 ]; then
  log "  ❌ Найдено $change_me_count строк с CHANGE_ME"
  docker compose exec -T api cat .env 2>/dev/null | grep "CHANGE_ME" | tee -a "$OUTPUT_FILE"
else
  log "  ✅ CHANGE_ME не найдено"
fi

log_section "5. MEMORY LIMITS И ИСПОЛЬЗОВАНИЕ"

log "Настроенные лимиты памяти:"
grep -A 3 "memory:" docker-compose.yml | grep -E "limits|memory" | tee -a "$OUTPUT_FILE"

log ""
log "Текущее использование памяти:"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | tee -a "$OUTPUT_FILE"

log ""
log "Проверка лимитов контейнеров:"
for container in email_api email_postgres email_postal email_sidekiq email_redis; do
  mem=$(docker inspect $container 2>/dev/null | grep -o '"Memory":[0-9]*' | head -1 | cut -d: -f2 || echo "0")
  mem_mb=$((mem / 1024 / 1024))
  if [ "$mem" -gt 0 ]; then
    log "  $container: ${mem_mb}MB"
  else
    log "  $container: No limit или контейнер не найден"
  fi
done

log_section "6. ПРОВЕРКА КОДА"

log "Deprecated 'rescue =>' синтаксис:"
deprecated_files=$(docker compose exec -T api find app/ -name "*.rb" -exec grep -l "rescue =>" {} \; 2>/dev/null | wc -l || echo "0")
log "  Найдено файлов: $deprecated_files"
if [ "$deprecated_files" -gt 0 ]; then
  log "  Примеры:"
  docker compose exec -T api find app/ -name "*.rb" -exec grep -Hn "rescue =>" {} \; 2>/dev/null | head -5 | tee -a "$OUTPUT_FILE"
fi

log ""
log "Broad exception handling (rescue StandardError):"
broad_rescue_count=$(docker compose exec -T api grep -r "rescue StandardError" app/ 2>/dev/null | wc -l || echo "0")
log "  Найдено мест: $broad_rescue_count"

log ""
log "IP-based authentication check:"
if docker compose exec -T api grep -q "client_ip.start_with?" app/controllers/api/v1/smtp_controller.rb 2>/dev/null; then
  log "  ❌ НАЙДЕНО: IP-based auth в smtp_controller.rb"
  docker compose exec -T api grep -A 3 "client_ip.start_with?" app/controllers/api/v1/smtp_controller.rb 2>&1 | tee -a "$OUTPUT_FILE"
else
  log "  ✅ IP-based auth не обнаружена"
fi

log ""
log "Weak encryption check (SECRET_KEY_BASE truncation):"
if docker compose exec -T api grep -q "secret_key_base\[0, 32\]" app/controllers/ 2>/dev/null; then
  log "  ❌ НАЙДЕНО: Weak encryption pattern"
  docker compose exec -T api grep -rn "secret_key_base\[0, 32\]" app/controllers/ 2>&1 | tee -a "$OUTPUT_FILE"
else
  log "  ✅ Weak encryption pattern не обнаружен"
fi

log_section "7. SMTP RELAY ПРОВЕРКА"

log "SMTP Relay конфигурация:"
log "  authOptional:"
docker compose exec -T smtp-relay grep "authOptional" server.js 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "  onAuth implementation:"
docker compose exec -T smtp-relay grep -A 5 "onAuth" server.js 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "  Size limit:"
docker compose exec -T smtp-relay grep "size:" server.js 2>&1 | tee -a "$OUTPUT_FILE"

log_section "8. ПРОВЕРКА API И СЕРВИСОВ"

log "API Health Check:"
docker compose exec -T api curl -s http://localhost:3000/api/v1/health 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Redis Connection:"
docker compose exec -T redis redis-cli ping 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "PostgreSQL версия:"
docker compose exec -T postgres psql -U email_sender -d email_sender -c "SHOW server_version;" 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "PostgreSQL настройки памяти:"
docker compose exec -T postgres psql -U email_sender -d email_sender -c "SHOW shared_buffers; SHOW effective_cache_size;" 2>&1 | tee -a "$OUTPUT_FILE"

log_section "9. SIDEKIQ СТАТИСТИКА"

log "Sidekiq Stats:"
docker compose exec -T api rails runner "
  require 'sidekiq/api'
  stats = Sidekiq::Stats.new
  puts \"Processed: #{stats.processed}\"
  puts \"Failed: #{stats.failed}\"
  puts \"Retry: #{stats.retry_size}\"
  puts \"Dead: #{stats.dead_size}\"
  puts \"Scheduled: #{stats.scheduled_size}\"
  puts \"Enqueued: #{stats.enqueued}\"
  puts \"Queues:\"
  Sidekiq::Queue.all.each do |q|
    puts \"  #{q.name}: #{q.size}\"
  end
" 2>&1 | tee -a "$OUTPUT_FILE"

log_section "10. ДАННЫЕ В БД (если есть)"

log "API Keys:"
docker compose exec -T api rails runner "
  if defined?(ApiKey) && ApiKey.table_exists?
    puts \"Всего: #{ApiKey.count}\"
    puts \"Активных: #{ApiKey.where(active: true).count}\"
    ApiKey.limit(3).each do |key|
      puts \"  - #{key.name}: active=#{key.active}, last_used=#{key.last_used_at}\"
    end
  else
    puts 'ApiKey таблица не существует'
  end
" 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Email Logs:"
docker compose exec -T api rails runner "
  if defined?(EmailLog) && EmailLog.table_exists?
    puts \"Всего: #{EmailLog.count}\"
    puts \"По статусам:\"
    EmailLog.group(:status).count.each do |status, count|
      puts \"  #{status}: #{count}\"
    end
  else
    puts 'EmailLog таблица не существует'
  end
" 2>&1 | tee -a "$OUTPUT_FILE"

log ""
log "Campaign Stats:"
docker compose exec -T api rails runner "
  if defined?(CampaignStats) && CampaignStats.table_exists?
    puts \"Всего кампаний: #{CampaignStats.count}\"
    total_sent = CampaignStats.sum(:total_sent)
    total_delivered = CampaignStats.sum(:total_delivered)
    puts \"Всего отправлено: #{total_sent}\"
    puts \"Всего доставлено: #{total_delivered}\"
  else
    puts 'CampaignStats таблица не существует'
  end
" 2>&1 | tee -a "$OUTPUT_FILE"

log_section "11. ЛОГИ (ПОСЛЕДНИЕ ОШИБКИ)"

log "API logs (последние 20 ERROR строк):"
docker compose logs api --tail=500 2>&1 | grep -i "error\|exception\|fatal" | tail -20 | tee -a "$OUTPUT_FILE" || log "Нет ошибок в логах"

log ""
log "PostgreSQL logs (последние 20 ERROR строк):"
docker compose logs postgres --tail=500 2>&1 | grep -i "error\|fatal" | tail -20 | tee -a "$OUTPUT_FILE" || log "Нет ошибок в логах"

log ""
log "Postal logs (последние 20 ERROR строк):"
docker compose logs postal --tail=500 2>&1 | grep -i "error\|exception\|fatal" | tail -20 | tee -a "$OUTPUT_FILE" || log "Нет ошибок в логах"

log_section "12. ПРОВЕРКА ФАЙЛОВОЙ СТРУКТУРЫ"

log "Важные файлы конфигурации:"
files=(
  ".env"
  "docker-compose.yml"
  "postal_public.key"
  "services/api/config/database.yml"
  "services/api/config/initializers/required_env.rb"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    log "  ✅ $file: EXISTS"
  else
    log "  ❌ $file: MISSING"
  fi
done

log_section "13. ОТКРЫТЫЕ ПОРТЫ"

log "Порты контейнеров:"
docker compose ps --format "table {{.Name}}\t{{.Ports}}" | tee -a "$OUTPUT_FILE"

log_section "ИТОГО"

log ""
log "Проверка завершена: $(date)"
log "Результаты сохранены в: $OUTPUT_FILE"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "✅ Детальная проверка завершена!"
echo "📄 Результаты сохранены в: $OUTPUT_FILE"
echo ""
echo "Рекомендации:"
echo "1. Откройте файл: cat $OUTPUT_FILE"
echo "2. Или просмотрите: less $OUTPUT_FILE"
echo "3. Поищите маркеры ❌ для критических проблем"
echo ""
