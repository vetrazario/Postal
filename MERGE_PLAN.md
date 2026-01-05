# План мержа веток в main

**Дата анализа:** $(Get-Date -Format "yyyy-MM-dd HH:mm")
**Текущая ветка:** dashboard_only
**Базовая ветка:** main (e5f8b99)

---

## 📊 Анализ веток

### Локальные ветки:
1. **main** - базовая ветка (e5f8b99)
2. **dashboard_only** - текущая ветка, содержит изменения dashboard
3. **DB_Fix** - фиксы безопасности и базы данных
4. **claude/setup-email-testing-YifKd** - настройка тестирования email
5. **claude/deep-analysis-fix-plan-nQT8o** - план фиксов
6. **claude/fix-ubuntu-installation-NOTvk** - фиксы установки Ubuntu
7. **claude/review-ams-connection-zuCc8** - на том же коммите что и main

### Удаленные ветки с важными изменениями:
1. **origin/claude/security-fixes-F6I8U** - КРИТИЧЕСКИ ВАЖНО! Много фиксов безопасности
2. **origin/claude/fix-tracking-unsubscribe-links-Fr6Lf** - фикс трекинга и unsubscribe
3. **origin/claude/fix-ai-analysis-display-6zxju** - фикс отображения AI анализа
4. **origin/claude/investigate-duplicate-modules-F6I8U** - уже смержен в dashboard_only

---

## 🎯 План мержа (по приоритету)

### Этап 1: Подготовка main
```bash
git checkout main
git pull origin main
```

### Этап 2: Мерж критических фиксов безопасности (ВЫСОКИЙ ПРИОРИТЕТ)

#### 2.1. origin/claude/security-fixes-F6I8U
**Содержит:**
- Fix critical security vulnerabilities
- Fix headers Map serialization in SMTP relay
- Add signing.key volume mount for Postal webhooks
- Handle MessageSent webhook event from Postal
- Fix webhook status mapping and improve logs UI
- Fix SMTP output color
- Redesign AI Analytics
- Allow any OpenRouter model in AI settings

**Команды:**
```bash
git checkout main
git fetch origin
git merge origin/claude/security-fixes-F6I8U --no-ff -m "Merge security fixes and improvements"
```

**Проверка конфликтов:**
```bash
git status
# Если есть конфликты - разрешить вручную
```

### Этап 3: Мерж фиксов функциональности

#### 3.1. origin/claude/fix-tracking-unsubscribe-links-Fr6Lf
**Содержит:**
- Fix tracking links to use HTTPS
- Add unsubscribe functionality

**Команды:**
```bash
git merge origin/claude/fix-tracking-unsubscribe-links-Fr6Lf --no-ff -m "Merge tracking and unsubscribe fixes"
```

#### 3.2. origin/claude/fix-ai-analysis-display-6zxju
**Содержит:**
- Fix AI analysis display: redirect instead of JSON
- Add proper result UI

**Команды:**
```bash
git merge origin/claude/fix-ai-analysis-display-6zxju --no-ff -m "Merge AI analysis display fixes"
```

### Этап 4: Мерж dashboard_only

**Содержит:**
- Remove SMTP Credentials, API Keys, Webhooks from sidebar navigation
- Force update dashboard index
- Merge from origin/claude/investigate-duplicate-modules-F6I8U

**Команды:**
```bash
git merge dashboard_only --no-ff -m "Merge dashboard changes"
```

**⚠️ ВНИМАНИЕ:** Эта ветка удаляет некоторые элементы из навигации. Убедитесь, что это нужно!

### Этап 5: Мерж DB_Fix

**Содержит:**
- Security: Remove AMS tracking headers from outgoing emails
- Fix: Extract campaign_id from email headers
- Fix: Use postal:5000 for API URL
- Fix: read public key from file instead of env var
- Уже содержит мерж claude/setup-email-testing-YifKd

**Команды:**
```bash
git merge DB_Fix --no-ff -m "Merge database and security fixes"
```

**⚠️ ВНИМАНИЕ:** Эта ветка уже содержит изменения из claude/setup-email-testing-YifKd, поэтому мержить claude/setup-email-testing-YifKd отдельно НЕ НУЖНО!

### Этап 6: Опциональные ветки

#### 6.1. claude/setup-email-testing-YifKd
**Статус:** ⚠️ УЖЕ ВКЛЮЧЕНА в DB_Fix
**Действие:** НЕ мержить отдельно, уже есть в DB_Fix

#### 6.2. claude/fix-ubuntu-installation-NOTvk
**Статус:** Проверить, нужны ли изменения
**Действие:** Проверить вручную, если нужно - мержить

#### 6.3. claude/deep-analysis-fix-plan-nQT8o
**Статус:** План фиксов
**Действие:** Проверить, применены ли фиксы, если да - не мержить

---

## 🔄 Рекомендуемая последовательность мержа

### Вариант 1: Консервативный (рекомендуется)

```bash
# 1. Подготовка
git checkout main
git pull origin main

# 2. Критические фиксы безопасности
git merge origin/claude/security-fixes-F6I8U --no-ff -m "Merge: Security fixes and improvements"

# 3. Фиксы функциональности
git merge origin/claude/fix-tracking-unsubscribe-links-Fr6Lf --no-ff -m "Merge: Tracking and unsubscribe fixes"
git merge origin/claude/fix-ai-analysis-display-6zxju --no-ff -m "Merge: AI analysis display fixes"

# 4. Dashboard изменения
git merge dashboard_only --no-ff -m "Merge: Dashboard navigation changes"

# 5. DB и дополнительные фиксы
git merge DB_Fix --no-ff -m "Merge: Database and security fixes"

# 6. Проверка и push
git log --oneline --graph -20
git push origin main
```

### Вариант 2: Агрессивный (все сразу)

```bash
git checkout main
git pull origin main
git merge origin/claude/security-fixes-F6I8U --no-ff -m "Merge: Security fixes"
git merge origin/claude/fix-tracking-unsubscribe-links-Fr6Lf --no-ff -m "Merge: Tracking fixes"
git merge origin/claude/fix-ai-analysis-display-6zxju --no-ff -m "Merge: AI fixes"
git merge dashboard_only --no-ff -m "Merge: Dashboard"
git merge DB_Fix --no-ff -m "Merge: DB fixes"
git push origin main
```

---

## ⚠️ Важные замечания

1. **dashboard_only удаляет элементы навигации** - убедитесь, что это нужно!
2. **DB_Fix уже содержит claude/setup-email-testing-YifKd** - не мержить дважды
3. **origin/claude/security-fixes-F6I8U** - самый важный мерж, содержит много критических фиксов
4. **Проверяйте конфликты после каждого мержа**
5. **Тестируйте после каждого мержа** (если возможно)

---

## 🔍 Проверка перед мержем

Перед каждым мержем проверяйте:

```bash
# Проверить, что нет незакоммиченных изменений
git status

# Посмотреть, что будет смержено
git log main..<branch_name> --oneline

# Посмотреть изменения в файлах
git diff main..<branch_name> --stat

# Проверить потенциальные конфликты
git merge --no-commit --no-ff <branch_name>
git merge --abort  # отменить проверку
```

---

## 📝 После мержа

1. Проверить, что все коммиты на месте:
   ```bash
   git log --oneline --graph -30
   ```

2. Проверить статус:
   ```bash
   git status
   ```

3. Запустить тесты (если есть):
   ```bash
   # Ваши команды для тестирования
   ```

4. Push в удаленный репозиторий:
   ```bash
   git push origin main
   ```

---

## 🚨 Откат в случае проблем

Если что-то пошло не так:

```bash
# Откатить последний мерж (если еще не запушен)
git reset --hard HEAD~1

# Или откатить к определенному коммиту
git reset --hard <commit_hash>

# Или создать новую ветку из старого состояния main
git checkout -b main-backup <old_commit_hash>
git checkout main
```

---

## ✅ Чеклист перед мержем

- [ ] Создать backup текущего main: `git branch main-backup main`
- [ ] Убедиться, что рабочая директория чистая: `git status`
- [ ] Обновить main: `git checkout main && git pull origin main`
- [ ] Проверить каждую ветку на конфликты
- [ ] Выполнить мерж по плану
- [ ] Проверить результат: `git log --oneline --graph -30`
- [ ] Протестировать (если возможно)
- [ ] Запушить: `git push origin main`

---

**Создано автоматически на основе анализа веток проекта**

