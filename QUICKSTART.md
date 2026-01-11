# ⚡ БЫСТРЫЙ СТАРТ - ПРОВЕРКА СЕРВЕРА

## 🎯 Самое главное

```bash
# 1. ПРОВЕРИТЬ СЕРВЕР (2 минуты)
./quick_check.sh

# 2. ЕСЛИ ЕСТЬ ПРОБЛЕМЫ - ИСПРАВИТЬ (30 минут)
cat IMMEDIATE_FIXES.md

# 3. ДЕТАЛЬНАЯ ПРОВЕРКА (5 минут)
./detailed_check.sh
```

---

## 📋 Команды проверки

### Быстрая проверка критических проблем
```bash
./quick_check.sh
```
**Результат:** Цветной отчет с приоритетами (2-3 минуты)

### Детальная проверка с сохранением
```bash
./detailed_check.sh
```
**Результат:** Файл `verification_results_*.txt` (5-7 минут)

### Просмотр результатов
```bash
# Последний отчет
cat verification_results_*.txt | less

# Только проблемы
grep "❌" verification_results_*.txt
```

---

## 🔴 Критические проблемы - как проверить

### 1. База данных
```bash
# Список таблиц (должно быть 15+)
docker compose exec api rails runner "puts ActiveRecord::Base.connection.tables.count"

# Статус миграций
docker compose exec api rails db:migrate:status
```

### 2. Docker socket
```bash
# Проверить наличие (НЕ должно быть!)
docker compose exec api ls -la /var/run/docker.sock
```

### 3. Webhook verification
```bash
# Проверить bypass (должно быть false или не задано)
docker compose exec api printenv SKIP_POSTAL_WEBHOOK_VERIFICATION
```

### 4. ENV переменные
```bash
# Проверить критические переменные
for var in SECRET_KEY_BASE ENCRYPTION_PRIMARY_KEY POSTAL_SIGNING_KEY; do
  echo -n "$var: "
  docker compose exec api printenv "$var" | cut -c1-20
done
```

### 5. Memory limits
```bash
# Текущее использование
docker stats --no-stream
```

---

## 🛠️ Быстрые исправления

### Применить миграции
```bash
docker compose exec api rails db:migrate
```

### Перезапустить сервисы
```bash
docker compose down && docker compose up -d
```

### Проверить логи
```bash
# Все логи
docker compose logs --tail=100

# Только ошибки
docker compose logs | grep -i error
```

### Health check
```bash
# API
curl http://localhost:3000/api/v1/health | jq

# PostgreSQL
docker compose exec postgres psql -U email_sender -d email_sender -c "SELECT 1;"

# Redis
docker compose exec redis redis-cli ping
```

---

## 📚 Документация

| Файл | Описание | Размер |
|------|----------|--------|
| **SUMMARY.md** | 👈 **НАЧНИТЕ ЗДЕСЬ** | Резюме всего |
| IMMEDIATE_FIXES.md | Критические исправления (30 мин) | 276 строк |
| FULL_ERROR_ANALYSIS_REPORT.md | Полный отчет (51 проблема) | 1047 строк |
| VERIFICATION_COMMANDS.md | Все команды проверки | 605 строк |
| ПРОВЕРКА_СЕРВЕРА.md | Руководство на русском | 333 строки |
| quick_check.sh | Скрипт быстрой проверки | Исполняемый |
| detailed_check.sh | Скрипт детальной проверки | Исполняемый |

---

## 🚨 Что делать если...

### Скрипт не запускается
```bash
chmod +x quick_check.sh detailed_check.sh
```

### Контейнеры не работают
```bash
docker compose ps
docker compose up -d
```

### Ошибка подключения к БД
```bash
docker compose logs postgres
docker compose restart postgres
```

### Миграции не применяются
```bash
docker compose exec api rails db:migrate RAILS_ENV=production
```

---

## ✅ Чеклист перед production

```bash
# 1. Миграции применены
docker compose exec api rails db:migrate:status | grep "up"

# 2. ENV переменные заданы
grep "CHANGE_ME" .env | wc -l  # Должно быть 0

# 3. Docker socket НЕ смонтирован
docker compose exec api test -e /var/run/docker.sock && echo "ПРОБЛЕМА!"

# 4. Webhook verification включена
docker compose exec api printenv SKIP_POSTAL_WEBHOOK_VERIFICATION  # Не должно быть 'true'

# 5. Все сервисы здоровы
docker compose ps | grep "healthy"

# 6. Нет ошибок в логах
docker compose logs --tail=100 | grep -i "error" | wc -l
```

---

## 🎯 Приоритеты

1. **СЕЙЧАС** (5 мин): `./quick_check.sh`
2. **СЕГОДНЯ** (30 мин): Исправить критические (если есть)
3. **ЭТА НЕДЕЛЯ** (2 часа): Исправить высокоприоритетные
4. **ЭТОТ МЕСЯЦ** (10 часов): Улучшения среднего приоритета

---

## 💡 Совет дня

> **Не паникуйте!** Если сервер работает - значит не все так плохо.
> Проблемы в отчете - это рекомендации для улучшения.
>
> Начните с `./quick_check.sh` - это покажет **реальное** состояние.

---

**Готово!** Запустите `./quick_check.sh` прямо сейчас! ⚡
