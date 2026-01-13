# 📋 ПРОСТОЙ ПЛАН: Управление Bounce Patterns

**Дата:** 2026-01-13
**Ветка:** `claude/bounce-patterns-management-Awt4F`
**Подход:** YAML файл + 3 кнопки на странице Mailing Rules
**Время:** 1-2 часа

---

## 🎯 ЦЕЛЬ

Дать возможность редактировать bounce patterns через Dashboard **БЕЗ** изменения кода.

### Было:
```ruby
# В коде - надо деплоить чтобы изменить
ERROR_PATTERNS = {...}.freeze
```

### Станет:
```yaml
# В файле - скачал, отредактировал, загрузил
rate_limit:
  patterns:
    - 'rate limit'
    - '421'
```

---

## 📦 ЧТО ДЕЛАЕМ

Всего **4 изменения**:

1. ✅ Создать файл `config/bounce_patterns.yml` с текущими паттернами
2. ✅ Изменить `error_classifier.rb` - читать из YAML вместо константы
3. ✅ Добавить 3 метода в `mailing_rules_controller.rb`
4. ✅ Добавить секцию "Bounce Patterns" на страницу Mailing Rules

**Никаких баз данных, никаких новых страниц, никаких миграций!**

---

## 📄 ФАЙЛ 1: config/bounce_patterns.yml

### Где создать:
```
services/api/config/bounce_patterns.yml
```

### Содержимое:

```yaml
# Bounce Pattern Configuration
# Редактируйте этот файл через Dashboard → Mailing Rules → Bounce Patterns

version: '1.0'

# Категории, которые НЕ добавляются в bounce list
non_bounce_categories:
  - rate_limit
  - temporary
  - connection

# Категории, при которых останавливать рассылку
stop_mailing_categories:
  - rate_limit
  - spam_block
  - mailbox_full
  - temporary
  - connection

# Паттерны для определения типа ошибки
patterns:
  rate_limit:
    description: "Rate limiting errors from email providers"
    patterns:
      - 'rate limit'
      - 'too many connections'
      - '421'
      - '429'
      - 'throttl'
      - 'connection rate limit'
      - 'too many messages'
      - 'receiving mail at a rate'
      - '5.7.1.*rate.*limit'

  spam_block:
    description: "Spam blocks and blacklist rejections"
    patterns:
      - 'spam'
      - 'blacklist'
      - 'blocked'
      - 'rejected'
      - 'dnsbl'
      - 'rbl'
      - 'spamhaus'
      - 'suspected spam'
      - '550 5.7.1'
      - 'message has been blocked'
      - 'likely spam'
      - 'policy restrictions'

  user_not_found:
    description: "User or mailbox not found errors"
    patterns:
      - 'user unknown'
      - 'mailbox not found'
      - 'does not exist'
      - '550 5.1.1'
      - 'no such user'
      - 'recipient not found'
      - 'invalid recipient'
      - 'unable to find recipient'

  mailbox_full:
    description: "Mailbox full or quota exceeded"
    patterns:
      - 'mailbox full'
      - 'quota exceeded'
      - 'over quota'
      - '552'
      - 'mailbox is full'
      - 'storage quota'
      - '550 5.2.1'
      - '552 5.2.2'
      - 'exceeded storage allocation'

  temporary:
    description: "Temporary delivery failures"
    patterns:
      - 'try again'
      - 'temporarily'
      - '4.7.'
      - 'greylisted'
      - 'temporary failure'
      - 'try later'
      - '421 4.7.0'
      - '450 4.2.1'
      - '451 4.5.1'
      - 'insufficient system storage'

  authentication:
    description: "SPF, DKIM, DMARC authentication failures"
    patterns:
      - 'authentication'
      - 'spf'
      - 'dkim'
      - 'dmarc'
      - 'authentication failed'
      - '550 5.7.23'
      - 'unauthenticated email is not accepted'
      - 'does not have authentication'
      - 'spf/dkim/dmarc failure'
      - 'tls required'

  connection:
    description: "Connection and network errors"
    patterns:
      - 'connection refused'
      - 'timeout'
      - 'unreachable'
      - 'connection error'
      - 'network error'
      - 'connection reset'
      - 'service not available'
      - 'closing transmission channel'
```

### Что это дает:
- ✅ Все паттерны в одном месте
- ✅ Можно редактировать любым редактором
- ✅ Комментарии для каждой категории
- ✅ Легко добавлять новые паттерны

---

## 🔧 ФАЙЛ 2: Изменения в error_classifier.rb

### Где менять:
```
services/api/app/services/error_classifier.rb
```

### Что менять:

#### БЫЛО (старые константы - закомментировать):

```ruby
class ErrorClassifier
  # ERROR_PATTERNS = {...}.freeze  # DEPRECATED - теперь в YAML
  # NON_BOUNCE_CATEGORIES = %w[...].freeze  # DEPRECATED
  # STOP_MAILING_CATEGORIES = %w[...].freeze  # DEPRECATED

  def self.classify(payload)
    # ... код ...
  end
end
```

#### СТАНЕТ (читаем из YAML):

```ruby
class ErrorClassifier
  class << self
    def classify(payload)
      output = extract_text(payload, :output) || ''
      details = extract_text(payload, :details) || ''
      status = extract_text(payload, :status) || ''

      full_text = "#{status} #{output} #{details}".downcase

      category = find_category(full_text)
      smtp_code = extract_smtp_code(output)

      {
        category: category,
        bounce_type: 'hard',
        smtp_code: smtp_code,
        message: output.presence || details.presence || status,
        should_add_to_bounce: should_add_to_bounce?(category),
        should_stop_mailing: should_stop_mailing?(category)
      }
    end

    private

    def find_category(text)
      config['patterns'].each do |category, data|
        patterns = data['patterns'] || []
        return category.to_sym if patterns.any? { |pattern| text.include?(pattern.downcase) }
      end
      :unknown
    end

    def should_add_to_bounce?(category)
      non_bounce = config['non_bounce_categories'] || []
      !non_bounce.include?(category.to_s)
    end

    def should_stop_mailing?(category)
      stop_categories = config['stop_mailing_categories'] || []
      stop_categories.include?(category.to_s)
    end

    def config
      @config ||= load_config
    end

    def load_config
      config_path = Rails.root.join('config', 'bounce_patterns.yml')
      YAML.load_file(config_path)
    rescue StandardError => e
      Rails.logger.error "Failed to load bounce patterns: #{e.message}"
      # Fallback к дефолтным значениям если файл не найден
      default_config
    end

    def default_config
      {
        'patterns' => {},
        'non_bounce_categories' => [],
        'stop_mailing_categories' => []
      }
    end

    # Метод для сброса кеша (вызывается после загрузки нового файла)
    def reload_config!
      @config = nil
    end

    def extract_text(payload, key)
      payload.dig(key) || payload.dig(key.to_s) || payload[key] || payload[key.to_s]
    end

    def extract_smtp_code(text)
      return nil if text.blank?
      match = text.match(/(\d{3})(?:\s+[\d.]+)?/)
      match ? match[1] : nil
    end
  end
end
```

### Изменения:
- ✅ Убрали константы `ERROR_PATTERNS`, `NON_BOUNCE_CATEGORIES`, `STOP_MAILING_CATEGORIES`
- ✅ Добавили метод `config` - загружает из YAML
- ✅ Добавили `reload_config!` - сбрасывает кеш после загрузки нового файла
- ✅ Добавили fallback на дефолтные значения если файл не найден
- ✅ **Всего ~40 строк кода**

---

## 🎮 ФАЙЛ 3: Добавить методы в mailing_rules_controller.rb

### Где менять:
```
services/api/app/controllers/dashboard/mailing_rules_controller.rb
```

### Что добавить:

```ruby
module Dashboard
  class MailingRulesController < BaseController
    def show
      @rule = MailingRule.instance
    end

    def update
      @rule = MailingRule.instance
      if @rule.update(mailing_rule_params)
        redirect_to dashboard_mailing_rules_path, notice: 'Mailing rules updated successfully'
      else
        render :show
      end
    end

    def test_ams_connection
      # ... существующий код ...
    end

    # ============ НОВЫЕ МЕТОДЫ ДЛЯ BOUNCE PATTERNS ============

    # GET /dashboard/mailing_rules/download_bounce_patterns
    def download_bounce_patterns
      config_path = Rails.root.join('config', 'bounce_patterns.yml')

      unless File.exist?(config_path)
        redirect_to dashboard_mailing_rules_path, alert: 'Bounce patterns file not found'
        return
      end

      send_file config_path,
                filename: "bounce_patterns_#{Time.current.to_i}.yml",
                type: 'application/x-yaml',
                disposition: 'attachment'
    end

    # POST /dashboard/mailing_rules/upload_bounce_patterns
    def upload_bounce_patterns
      uploaded_file = params[:bounce_patterns_file]

      unless uploaded_file
        redirect_to dashboard_mailing_rules_path, alert: 'No file selected'
        return
      end

      begin
        # Валидируем YAML
        yaml_content = uploaded_file.read
        parsed = YAML.safe_load(yaml_content)

        # Проверяем структуру
        unless parsed.is_a?(Hash) && parsed['patterns'].is_a?(Hash)
          raise 'Invalid file structure. Must contain "patterns" key.'
        end

        # Создаем бэкап текущего файла
        config_path = Rails.root.join('config', 'bounce_patterns.yml')
        backup_path = Rails.root.join('config', "bounce_patterns.backup.#{Time.current.to_i}.yml")
        FileUtils.cp(config_path, backup_path) if File.exist?(config_path)

        # Сохраняем новый файл
        File.write(config_path, yaml_content)

        # Сбрасываем кеш в ErrorClassifier
        ErrorClassifier.reload_config!

        redirect_to dashboard_mailing_rules_path,
                    notice: "Bounce patterns updated successfully. Backup saved to #{backup_path.basename}"
      rescue StandardError => e
        redirect_to dashboard_mailing_rules_path,
                    alert: "Failed to upload: #{e.message}"
      end
    end

    # POST /dashboard/mailing_rules/reset_bounce_patterns
    def reset_bounce_patterns
      begin
        config_path = Rails.root.join('config', 'bounce_patterns.yml')

        # Создаем бэкап текущего файла
        if File.exist?(config_path)
          backup_path = Rails.root.join('config', "bounce_patterns.backup.#{Time.current.to_i}.yml")
          FileUtils.cp(config_path, backup_path)
        end

        # Восстанавливаем дефолтный конфиг (можно либо из git, либо захардкоженный)
        default_content = File.read(Rails.root.join('config', 'bounce_patterns.default.yml'))
        File.write(config_path, default_content)

        # Сбрасываем кеш
        ErrorClassifier.reload_config!

        redirect_to dashboard_mailing_rules_path,
                    notice: 'Bounce patterns reset to defaults'
      rescue StandardError => e
        redirect_to dashboard_mailing_rules_path,
                    alert: "Failed to reset: #{e.message}"
      end
    end

    private

    def mailing_rule_params
      # ... существующий код ...
    end
  end
end
```

### Что добавили:
- ✅ `download_bounce_patterns` - скачать текущий YAML
- ✅ `upload_bounce_patterns` - загрузить новый YAML (с валидацией и бэкапом)
- ✅ `reset_bounce_patterns` - сбросить к дефолтным
- ✅ **Всего ~60 строк кода**

---

## 🎨 ФАЙЛ 4: Добавить секцию в show.html.erb

### Где менять:
```
services/api/app/views/dashboard/mailing_rules/show.html.erb
```

### Что добавить (между существующими секциями):

```erb
<!-- Bounce Patterns -->
<div class="rounded-md bg-white shadow-sm ring-1 ring-gray-900/5">
  <div class="px-4 py-6 sm:p-8">
    <h2 class="text-lg font-semibold text-gray-900 mb-4">Bounce Patterns</h2>
    <p class="text-sm text-gray-600 mb-6">
      Manage error patterns for bounce classification. Download the config file,
      edit patterns locally, and upload back.
    </p>

    <div class="grid max-w-2xl grid-cols-1 gap-4">
      <!-- Download -->
      <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
        <div>
          <h3 class="text-sm font-medium text-gray-900">Download Configuration</h3>
          <p class="text-sm text-gray-500">Get current bounce patterns YAML file</p>
        </div>
        <%= link_to download_bounce_patterns_dashboard_mailing_rules_path,
                    class: "rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50" do %>
          📥 Download
        <% end %>
      </div>

      <!-- Upload -->
      <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
        <div>
          <h3 class="text-sm font-medium text-gray-900">Upload Configuration</h3>
          <p class="text-sm text-gray-500">Upload edited YAML file (backup created automatically)</p>
        </div>
        <button type="button"
                onclick="document.getElementById('bounce-patterns-upload').click()"
                class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500">
          📤 Upload
        </button>
      </div>

      <!-- Reset -->
      <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
        <div>
          <h3 class="text-sm font-medium text-gray-900">Reset to Defaults</h3>
          <p class="text-sm text-gray-500">Restore original bounce patterns (backup created)</p>
        </div>
        <%= button_to '🔄 Reset',
                      reset_bounce_patterns_dashboard_mailing_rules_path,
                      method: :post,
                      data: { confirm: 'Reset to default bounce patterns? Current config will be backed up.' },
                      class: "rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500" %>
      </div>

      <!-- Информация -->
      <div class="mt-4 p-4 bg-blue-50 rounded-lg">
        <h4 class="text-sm font-medium text-blue-900 mb-2">💡 How to edit patterns:</h4>
        <ol class="text-sm text-blue-700 space-y-1 list-decimal list-inside">
          <li>Click "Download" to get current configuration</li>
          <li>Edit the YAML file with any text editor</li>
          <li>Add/remove patterns under each category</li>
          <li>Click "Upload" to apply changes</li>
          <li>Changes take effect immediately</li>
        </ol>
        <p class="mt-3 text-sm text-blue-600">
          <strong>Example:</strong> To add Gmail rate limit pattern, add <code>'Gmail rate limit: 450 4.2.1'</code>
          under <code>rate_limit → patterns</code>
        </p>
      </div>
    </div>
  </div>
</div>

<!-- Hidden file input for upload -->
<%= form_with url: upload_bounce_patterns_dashboard_mailing_rules_path,
              multipart: true,
              id: 'bounce-patterns-form',
              class: 'hidden' do |f| %>
  <%= f.file_field :bounce_patterns_file,
                   id: 'bounce-patterns-upload',
                   accept: '.yml,.yaml',
                   onchange: 'this.form.submit()' %>
<% end %>
```

### Где вставить:
Между секцией "AMS API Connection" и секцией "Stop Thresholds". Примерно после строки 49.

### Что это дает:
- ✅ Красивый UI в стиле существующих секций
- ✅ 3 кнопки: Download, Upload, Reset
- ✅ Инструкция для пользователя
- ✅ Автоматический submit при выборе файла
- ✅ Подтверждение перед reset
- ✅ **Всего ~60 строк HTML**

---

## 🛣️ ФАЙЛ 5: Добавить routes

### Где менять:
```
services/api/config/routes.rb
```

### Что добавить:

```ruby
Rails.application.routes.draw do
  namespace :dashboard do
    # ... existing routes ...

    resource :mailing_rules, only: [:show, :update] do
      collection do
        post :test_ams_connection
        # Новые маршруты:
        get :download_bounce_patterns
        post :upload_bounce_patterns
        post :reset_bounce_patterns
      end
    end
  end
end
```

### Изменения:
- ✅ Добавили 3 маршрута
- ✅ **Всего 3 строки**

---

## 📋 КРАТКАЯ СВОДКА

### Что создается:

| Файл | Действие | Строк кода |
|------|----------|------------|
| `config/bounce_patterns.yml` | **Создать** | ~120 |
| `config/bounce_patterns.default.yml` | **Создать** (копия) | ~120 |
| `app/services/error_classifier.rb` | **Изменить** | ~40 |
| `app/controllers/dashboard/mailing_rules_controller.rb` | **Добавить** | ~60 |
| `app/views/dashboard/mailing_rules/show.html.erb` | **Добавить** | ~60 |
| `config/routes.rb` | **Добавить** | ~3 |
| **ИТОГО** | | **~400 строк** |

### Что НЕ делаем:
- ❌ База данных
- ❌ Миграции
- ❌ Новые страницы
- ❌ Сложные формы
- ❌ JavaScript фреймворки
- ❌ API endpoints
- ❌ Тесты (можно добавить потом)

---

## 🎯 КАК ИСПОЛЬЗОВАТЬ

### Для администратора:

1. **Зайти в Dashboard → Mailing Rules**
2. **Прокрутить к секции "Bounce Patterns"**
3. **Нажать "Download"** - скачается `bounce_patterns_1234567890.yml`
4. **Открыть файл в редакторе** (VSCode, Sublime, даже Notepad)
5. **Добавить новый паттерн:**
   ```yaml
   rate_limit:
     patterns:
       - 'rate limit'
       - '421'
       - 'Gmail specific error'  # ← новый паттерн
   ```
6. **Сохранить файл**
7. **Вернуться в Dashboard → Mailing Rules**
8. **Нажать "Upload"** - выбрать отредактированный файл
9. **✅ Готово!** Изменения применяются мгновенно

### Если что-то пошло не так:
- Автоматически создается бэкап: `bounce_patterns.backup.1234567890.yml`
- Можно нажать **"Reset to Defaults"** - вернутся оригинальные паттерны

---

## ✅ ПРОВЕРКА РАБОТОСПОСОБНОСТИ

### После реализации проверить:

```bash
# 1. Проверить что файл создан
ls -la services/api/config/bounce_patterns.yml

# 2. Проверить что ErrorClassifier читает из файла
docker compose exec api rails console
> ErrorClassifier.classify({output: "421 rate limit"})
# => {:category=>:rate_limit, :should_stop_mailing=>true, ...}

# 3. В браузере открыть Dashboard → Mailing Rules
# Должна быть новая секция "Bounce Patterns"

# 4. Нажать Download - должен скачаться YAML файл

# 5. Нажать Upload - загрузить тот же файл - должно работать

# 6. Нажать Reset - должно вернуть к дефолтам
```

---

## 📦 ПОРЯДОК РЕАЛИЗАЦИИ

```
Шаг 1 (10 минут):
  ├─ Создать config/bounce_patterns.yml
  └─ Создать config/bounce_patterns.default.yml (копия)

Шаг 2 (15 минут):
  └─ Изменить error_classifier.rb

Шаг 3 (20 минут):
  └─ Добавить методы в mailing_rules_controller.rb

Шаг 4 (15 минут):
  └─ Добавить секцию в show.html.erb

Шаг 5 (5 минут):
  └─ Добавить routes

Шаг 6 (20 минут):
  ├─ Тестирование
  ├─ Проверка UI
  └─ Проверка функционала

ИТОГО: ~1.5 часа
```

---

## 🚀 ПРЕИМУЩЕСТВА ПОДХОДА

✅ **Простота** - всего 4 файла, минимум кода
✅ **Не ломаем существующее** - все добавляется, ничего не удаляется
✅ **Логичное место** - bounce patterns это часть mailing rules
✅ **Бэкапы** - автоматически создаются при изменениях
✅ **Rollback** - всегда можно вернуться к дефолтам
✅ **Git-friendly** - YAML файлы можно коммитить
✅ **Переносимость** - скачал на одном сервере, загрузил на другом
✅ **Нет зависимостей** - используем только стандартный YAML
✅ **Быстро** - изменения применяются мгновенно

---

## ❓ ВОПРОСЫ И ОТВЕТЫ

**Q: Нужен ли рестарт после изменения файла?**
A: Нет. После загрузки вызывается `ErrorClassifier.reload_config!` - кеш сбрасывается.

**Q: Что если файл поврежден?**
A: Есть валидация при загрузке + автоматический бэкап. Можно нажать Reset.

**Q: Можно ли версионировать конфиг в git?**
A: Да! Файл в `config/` - можно коммитить как обычно.

**Q: Как синхронизировать между серверами?**
A: Скачать на одном → загрузить на другом. Или через git.

**Q: Можно ли редактировать прямо на сервере?**
A: Да, можно `nano config/bounce_patterns.yml` → потом в Dashboard нажать Reset (он перечитает).

---

## ✅ ГОТОВО К РЕАЛИЗАЦИИ

Этот план:
- ✅ Простой и понятный
- ✅ Не утяжеляет проект
- ✅ Использует существующую страницу
- ✅ Минимум изменений (~400 строк)
- ✅ Быстрая реализация (~1.5 часа)

**Начинаем?** 🚀
