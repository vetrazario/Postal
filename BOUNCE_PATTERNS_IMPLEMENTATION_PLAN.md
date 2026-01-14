# 🎯 ПЛАН РЕАЛИЗАЦИИ: Управление Bounce Patterns через Dashboard

**Дата создания:** 2026-01-13
**Ветка:** `claude/bounce-patterns-management-Awt4F`
**Подход:** Гибридный (БД + экспорт/импорт YAML)
**Приоритет:** Средний
**Статус:** 📝 Планирование

---

## 📋 СОДЕРЖАНИЕ

1. [Обзор и Цели](#обзор-и-цели)
2. [Текущее Состояние](#текущее-состояние)
3. [Архитектура Решения](#архитектура-решения)
4. [Детальный План Работ](#детальный-план-работ)
5. [База Данных](#база-данных)
6. [Backend Реализация](#backend-реализация)
7. [Frontend Реализация](#frontend-реализация)
8. [Миграция Данных](#миграция-данных)
9. [Тестирование](#тестирование)
10. [План Отката](#план-отката)
11. [Таймлайн](#таймлайн)

---

## 🎯 ОБЗОР И ЦЕЛИ

### Проблема

Сейчас bounce patterns (шаблоны для определения типа ошибок доставки) захардкожены в коде:

```ruby
# services/api/app/services/error_classifier.rb
ERROR_PATTERNS = {
  rate_limit: ['rate limit', 'too many connections', '421', '429', ...],
  spam_block: ['spam', 'blacklist', 'blocked', 'rejected', ...],
  # ... еще 5 категорий
}.freeze
```

**Последствия:**
- ❌ Нельзя добавить новый паттерн без изменения кода
- ❌ Нельзя отключить неработающий паттерн
- ❌ Нельзя настроить под специфику провайдеров
- ❌ Требуется деплой для любых изменений

### Цель

Создать систему управления bounce patterns через Dashboard с возможностью:
- ✅ Добавлять/редактировать/удалять паттерны через UI
- ✅ Активировать/деактивировать паттерны без удаления
- ✅ Экспортировать конфигурацию в YAML
- ✅ Импортировать конфигурацию из YAML
- ✅ Сбрасывать к дефолтным настройкам
- ✅ Изменения применяются мгновенно (без рестарта)

### Бизнес-ценность

1. **Гибкость:** Быстрая адаптация под новые типы ошибок провайдеров
2. **Контроль:** Визуальное управление вместо редактирования кода
3. **Переносимость:** Экспорт/импорт для синхронизации между серверами
4. **Безопасность:** Откат к дефолтным настройкам одной кнопкой

---

## 📊 ТЕКУЩЕЕ СОСТОЯНИЕ

### Где находятся паттерны сейчас

**Файл:** `services/api/app/services/error_classifier.rb`

**Структура данных:**
```ruby
# Паттерны для определения категорий ошибок
ERROR_PATTERNS = {
  rate_limit: [
    'rate limit', 'too many connections', '421', '429',
    'throttl', 'connection rate limit', 'too many messages',
    'receiving mail at a rate', '5.7.1.*rate.*limit'
  ],
  spam_block: [
    'spam', 'blacklist', 'blocked', 'rejected', 'dnsbl',
    'rbl', 'spamhaus', 'suspected spam', '550 5.7.1',
    'message has been blocked', 'likely spam', 'policy restrictions'
  ],
  user_not_found: [
    'user unknown', 'mailbox not found', 'does not exist',
    '550 5.1.1', 'no such user', 'recipient not found',
    'invalid recipient', 'unable to find recipient'
  ],
  mailbox_full: [
    'mailbox full', 'quota exceeded', 'over quota', '552',
    'mailbox is full', 'storage quota', '550 5.2.1',
    '552 5.2.2', 'exceeded storage allocation'
  ],
  temporary: [
    'try again', 'temporarily', '4.7.', 'greylisted',
    'temporary failure', 'try later', '421 4.7.0',
    '450 4.2.1', '451 4.5.1', 'insufficient system storage'
  ],
  authentication: [
    'authentication', 'spf', 'dkim', 'dmarc',
    'authentication failed', '550 5.7.23',
    'unauthenticated email is not accepted',
    'does not have authentication', 'spf/dkim/dmarc failure',
    'tls required'
  ],
  connection: [
    'connection refused', 'timeout', 'unreachable',
    'connection error', 'network error', 'connection reset',
    'service not available', 'closing transmission channel'
  ]
}.freeze

# Категории, которые НЕ добавлять в bounce list
NON_BOUNCE_CATEGORIES = %w[rate_limit temporary connection].freeze

# Категории, при которых останавливать рассылку
STOP_MAILING_CATEGORIES = %w[rate_limit spam_block mailbox_full temporary connection].freeze
```

**Как используется:**
```ruby
def classify(payload)
  # Извлекаем текст из payload
  full_text = "#{status} #{output} #{details}".downcase

  # Ищем категорию
  category = find_category(full_text)

  # Определяем действия
  should_add_to_bounce = !NON_BOUNCE_CATEGORIES.include?(category.to_s)
  should_stop_mailing = STOP_MAILING_CATEGORIES.include?(category.to_s)

  { category: category, should_add_to_bounce: should_add_to_bounce, ... }
end

private

def find_category(text)
  ERROR_PATTERNS.each do |category, patterns|
    return category if patterns.any? { |pattern| text.include?(pattern.downcase) }
  end
  :unknown
end
```

### Существующие UI компоненты

Уже есть похожий функционал для управления Mailing Rules:

**Controller:** `services/api/app/controllers/dashboard/mailing_rules_controller.rb`
**View:** `services/api/app/views/dashboard/mailing_rules/show.html.erb`
**Model:** `services/api/app/models/mailing_rule.rb`

**Можем использовать как референс:**
- Структура форм
- Стилизация (Tailwind CSS)
- Flash messages
- Валидация

---

## 🏗️ АРХИТЕКТУРА РЕШЕНИЯ

### Гибридный подход

**База данных:** Основное хранилище для runtime использования
**YAML экспорт/импорт:** Для бэкапов, переноса между серверами, версионирования

```
┌─────────────────────────────────────────────────────────────┐
│                        DASHBOARD UI                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Manage       │  │ Export to    │  │ Import from  │      │
│  │ Patterns     │  │ YAML         │  │ YAML         │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                  │               │
└─────────┼─────────────────┼──────────────────┼───────────────┘
          │                 │                  │
          ▼                 ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│              BouncePatterns Controller                       │
│  • index, create, update, destroy, activate/deactivate      │
│  • export_yaml, import_yaml, reset_to_defaults              │
└─────────────────────┬───────────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌──────────────────┐    ┌──────────────────┐
│ BouncePattern    │    │ BouncePattern    │
│ Model            │    │ YamlService      │
│ • Validations    │    │ • Export         │
│ • Scopes         │    │ • Import         │
│ • Associations   │    │ • Validate       │
└────────┬─────────┘    └──────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│   bounce_patterns table          │
│  • id, category, pattern, active │
│  • should_add_to_bounce          │
│  • should_stop_mailing           │
│  • description, created_at, etc  │
└──────────────────────────────────┘
         │
         │ (используется в runtime)
         ▼
┌──────────────────────────────────┐
│   ErrorClassifier Service        │
│  • classify(payload)             │
│  • find_category(text) - читает  │
│    паттерны из БД вместо констант│
└──────────────────────────────────┘
```

### Преимущества гибридного подхода

1. **Performance:** БД с индексами = быстрый поиск
2. **Flexibility:** UI для изменений на лету
3. **Portability:** YAML для бэкапов и миграций
4. **Version Control:** YAML файлы можно коммитить в git
5. **Disaster Recovery:** Всегда можно восстановить из YAML

---

## 📝 ДЕТАЛЬНЫЙ ПЛАН РАБОТ

### Этап 1: База Данных ✅ (2 часа)

**Задачи:**
1. ✅ Создать миграцию для таблицы `bounce_patterns`
2. ✅ Создать индексы для оптимизации поиска
3. ✅ Создать seed файл с дефолтными паттернами

**Файлы:**
- `db/migrate/YYYYMMDDHHMMSS_create_bounce_patterns.rb`
- `db/seeds/bounce_patterns_seed.rb`

---

### Этап 2: Backend Models (1.5 часа)

**Задачи:**
1. ✅ Создать модель `BouncePattern`
2. ✅ Добавить валидации
3. ✅ Добавить scopes для удобного доступа
4. ✅ Добавить методы для категорий

**Файлы:**
- `app/models/bounce_pattern.rb`

---

### Этап 3: Backend Services (2 часа)

**Задачи:**
1. ✅ Создать `BouncePatternYamlService` для экспорта/импорта
2. ✅ Обновить `ErrorClassifier` для использования БД
3. ✅ Добавить кеширование для производительности

**Файлы:**
- `app/services/bounce_pattern_yaml_service.rb`
- `app/services/error_classifier.rb` (модификация)

---

### Этап 4: Backend Controllers (1.5 часа)

**Задачи:**
1. ✅ Создать `Dashboard::BouncePatternsController`
2. ✅ Добавить actions: index, create, update, destroy
3. ✅ Добавить actions: toggle_active, export_yaml, import_yaml, reset_defaults
4. ✅ Добавить обработку ошибок и flash messages

**Файлы:**
- `app/controllers/dashboard/bounce_patterns_controller.rb`

---

### Этап 5: Frontend Views (3 часа)

**Задачи:**
1. ✅ Создать главную страницу управления паттернами
2. ✅ Создать формы создания/редактирования
3. ✅ Создать модальные окна для действий
4. ✅ Добавить фильтрацию и поиск
5. ✅ Создать UI для экспорта/импорта YAML

**Файлы:**
- `app/views/dashboard/bounce_patterns/index.html.erb`
- `app/views/dashboard/bounce_patterns/_form.html.erb`
- `app/views/dashboard/bounce_patterns/_pattern_row.html.erb`

---

### Этап 6: Frontend JavaScript (1.5 часа)

**Задачи:**
1. ✅ Добавить интерактивность (модальные окна)
2. ✅ Добавить клиентскую валидацию
3. ✅ Добавить AJAX для toggle активации
4. ✅ Добавить drag-and-drop для импорта YAML

**Файлы:**
- `app/assets/javascripts/dashboard/bounce_patterns.js`

---

### Этап 7: Routes & Navigation (0.5 часа)

**Задачи:**
1. ✅ Добавить маршруты
2. ✅ Добавить пункт меню в Dashboard

**Файлы:**
- `config/routes.rb`
- `app/views/layouts/dashboard/_sidebar.html.erb` (если есть)

---

### Этап 8: Testing (2 часа)

**Задачи:**
1. ✅ Unit тесты для модели
2. ✅ Unit тесты для сервисов
3. ✅ Integration тесты для контроллера
4. ✅ Тесты для ErrorClassifier

**Файлы:**
- `spec/models/bounce_pattern_spec.rb`
- `spec/services/bounce_pattern_yaml_service_spec.rb`
- `spec/services/error_classifier_spec.rb`
- `spec/controllers/dashboard/bounce_patterns_controller_spec.rb`

---

### Этап 9: Миграция данных (1 час)

**Задачи:**
1. ✅ Запустить миграцию
2. ✅ Запустить seed для загрузки дефолтных паттернов
3. ✅ Проверить работу ErrorClassifier с БД
4. ✅ Убедиться, что старые константы можно удалить

---

### Этап 10: Документация (1 час)

**Задачи:**
1. ✅ Документация API endpoints
2. ✅ Инструкция по использованию UI
3. ✅ Формат YAML для импорта/экспорта
4. ✅ Примеры кастомных паттернов

**Файлы:**
- `docs/BOUNCE_PATTERNS_GUIDE.md`

---

## 🗄️ БАЗА ДАННЫХ

### Схема таблицы

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_bounce_patterns.rb
class CreateBouncePatterns < ActiveRecord::Migration[7.1]
  def change
    create_table :bounce_patterns do |t|
      # Основные поля
      t.string :category, null: false, index: true
      # Категории: rate_limit, spam_block, user_not_found, mailbox_full,
      #            temporary, authentication, connection, unknown

      t.string :pattern, null: false
      # Текст для поиска, например: 'rate limit', '421', 'spam'

      t.boolean :active, default: true, null: false, index: true
      # Включен ли паттерн (можно отключить без удаления)

      # Поведение при совпадении
      t.boolean :should_add_to_bounce, default: true, null: false
      # Добавлять ли email в bounce list при совпадении

      t.boolean :should_stop_mailing, default: false, null: false
      # Останавливать ли рассылку при совпадении

      # Дополнительно
      t.text :description
      # Описание паттерна для пользователей

      t.integer :priority, default: 0, null: false
      # Приоритет (для порядка проверки, если нужно)

      t.boolean :is_default, default: false, null: false
      # Дефолтный паттерн (не удаляется при reset)

      t.timestamps
    end

    # Составной индекс для быстрого поиска активных паттернов по категории
    add_index :bounce_patterns, [:category, :active]

    # Уникальность: одна комбинация категория+паттерн
    add_index :bounce_patterns, [:category, :pattern], unique: true

    # Индекс для сортировки по приоритету
    add_index :bounce_patterns, :priority
  end
end
```

### SQL для создания (PostgreSQL)

```sql
CREATE TABLE bounce_patterns (
  id BIGSERIAL PRIMARY KEY,
  category VARCHAR NOT NULL,
  pattern VARCHAR NOT NULL,
  active BOOLEAN DEFAULT TRUE NOT NULL,
  should_add_to_bounce BOOLEAN DEFAULT TRUE NOT NULL,
  should_stop_mailing BOOLEAN DEFAULT FALSE NOT NULL,
  description TEXT,
  priority INTEGER DEFAULT 0 NOT NULL,
  is_default BOOLEAN DEFAULT FALSE NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX index_bounce_patterns_on_category ON bounce_patterns (category);
CREATE INDEX index_bounce_patterns_on_active ON bounce_patterns (active);
CREATE INDEX index_bounce_patterns_on_category_and_active ON bounce_patterns (category, active);
CREATE INDEX index_bounce_patterns_on_priority ON bounce_patterns (priority);
CREATE UNIQUE INDEX index_bounce_patterns_on_category_and_pattern ON bounce_patterns (category, pattern);
```

### Seed данных

```ruby
# db/seeds/bounce_patterns_seed.rb

puts "🌱 Seeding bounce patterns..."

# Определяем категории и их поведение
CATEGORY_BEHAVIORS = {
  rate_limit: {
    should_add_to_bounce: false,  # Проблема скорости, а не качества адреса
    should_stop_mailing: true,    # Нужно остановить рассылку
    description: "Rate limiting errors from email providers"
  },
  spam_block: {
    should_add_to_bounce: true,
    should_stop_mailing: true,
    description: "Spam blocks and blacklist rejections"
  },
  user_not_found: {
    should_add_to_bounce: true,
    should_stop_mailing: false,
    description: "User or mailbox not found errors"
  },
  mailbox_full: {
    should_add_to_bounce: true,
    should_stop_mailing: true,
    description: "Mailbox full or quota exceeded"
  },
  temporary: {
    should_add_to_bounce: false,
    should_stop_mailing: true,
    description: "Temporary delivery failures"
  },
  authentication: {
    should_add_to_bounce: true,
    should_stop_mailing: false,
    description: "SPF, DKIM, DMARC authentication failures"
  },
  connection: {
    should_add_to_bounce: false,
    should_stop_mailing: true,
    description: "Connection and network errors"
  }
}.freeze

# Паттерны из текущего ERROR_PATTERNS
DEFAULT_PATTERNS = {
  rate_limit: [
    'rate limit', 'too many connections', '421', '429',
    'throttl', 'connection rate limit', 'too many messages',
    'receiving mail at a rate', '5.7.1.*rate.*limit'
  ],
  spam_block: [
    'spam', 'blacklist', 'blocked', 'rejected', 'dnsbl',
    'rbl', 'spamhaus', 'suspected spam', '550 5.7.1',
    'message has been blocked', 'likely spam', 'policy restrictions'
  ],
  user_not_found: [
    'user unknown', 'mailbox not found', 'does not exist',
    '550 5.1.1', 'no such user', 'recipient not found',
    'invalid recipient', 'unable to find recipient'
  ],
  mailbox_full: [
    'mailbox full', 'quota exceeded', 'over quota', '552',
    'mailbox is full', 'storage quota', '550 5.2.1',
    '552 5.2.2', 'exceeded storage allocation'
  ],
  temporary: [
    'try again', 'temporarily', '4.7.', 'greylisted',
    'temporary failure', 'try later', '421 4.7.0',
    '450 4.2.1', '451 4.5.1', 'insufficient system storage'
  ],
  authentication: [
    'authentication', 'spf', 'dkim', 'dmarc',
    'authentication failed', '550 5.7.23',
    'unauthenticated email is not accepted',
    'does not have authentication', 'spf/dkim/dmarc failure',
    'tls required'
  ],
  connection: [
    'connection refused', 'timeout', 'unreachable',
    'connection error', 'network error', 'connection reset',
    'service not available', 'closing transmission channel'
  ]
}.freeze

# Создаем записи
created_count = 0
DEFAULT_PATTERNS.each do |category, patterns|
  behavior = CATEGORY_BEHAVIORS[category]

  patterns.each_with_index do |pattern, index|
    BouncePattern.create!(
      category: category.to_s,
      pattern: pattern,
      active: true,
      should_add_to_bounce: behavior[:should_add_to_bounce],
      should_stop_mailing: behavior[:should_stop_mailing],
      description: behavior[:description],
      priority: index,  # Порядок как в оригинальном массиве
      is_default: true  # Помечаем как дефолтные
    )
    created_count += 1
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️  Skipped duplicate: #{category}/#{pattern}"
  end
end

puts "✅ Created #{created_count} bounce patterns"

# Показываем статистику
puts "\n📊 Statistics:"
BouncePattern.group(:category).count.each do |category, count|
  puts "  #{category}: #{count} patterns"
end
```

---

## 🔧 BACKEND РЕАЛИЗАЦИЯ

### 1. Модель BouncePattern

```ruby
# app/models/bounce_pattern.rb
class BouncePattern < ApplicationRecord
  # Validations
  validates :category, presence: true, inclusion: {
    in: %w[rate_limit spam_block user_not_found mailbox_full temporary authentication connection unknown],
    message: "%{value} is not a valid category"
  }
  validates :pattern, presence: true, length: { minimum: 1, maximum: 255 }
  validates :pattern, uniqueness: { scope: :category, message: "already exists for this category" }

  # Default values
  attribute :active, :boolean, default: true
  attribute :should_add_to_bounce, :boolean, default: true
  attribute :should_stop_mailing, :boolean, default: false
  attribute :priority, :integer, default: 0
  attribute :is_default, :boolean, default: false

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_category, ->(category) { where(category: category) }
  scope :ordered, -> { order(priority: :asc, created_at: :asc) }
  scope :defaults, -> { where(is_default: true) }
  scope :custom, -> { where(is_default: false) }

  # Class methods
  def self.categories
    %w[rate_limit spam_block user_not_found mailbox_full temporary authentication connection unknown]
  end

  def self.for_classification
    # Группируем активные паттерны по категориям для быстрого доступа
    active.ordered.group_by(&:category).transform_values { |patterns| patterns.map(&:pattern) }
  end

  def self.reset_to_defaults!
    # Удаляем все кастомные паттерны
    custom.destroy_all

    # Активируем все дефолтные
    defaults.update_all(active: true)
  end

  # Instance methods
  def toggle_active!
    update!(active: !active)
  end

  def category_human
    category.humanize.titleize
  end
end
```

---

### 2. Service: BouncePatternYamlService

```ruby
# app/services/bounce_pattern_yaml_service.rb
require 'yaml'

class BouncePatternYamlService
  class ImportError < StandardError; end

  # Экспорт в YAML
  def self.export
    patterns_data = BouncePattern.ordered.map do |pattern|
      {
        'category' => pattern.category,
        'pattern' => pattern.pattern,
        'active' => pattern.active,
        'should_add_to_bounce' => pattern.should_add_to_bounce,
        'should_stop_mailing' => pattern.should_stop_mailing,
        'description' => pattern.description,
        'priority' => pattern.priority,
        'is_default' => pattern.is_default
      }
    end

    {
      'version' => '1.0',
      'exported_at' => Time.current.iso8601,
      'patterns_count' => patterns_data.size,
      'patterns' => patterns_data
    }.to_yaml
  end

  # Импорт из YAML
  def self.import(yaml_content, mode: :merge)
    # mode: :merge (добавить новые, обновить существующие)
    #       :replace (удалить все, загрузить из YAML)

    data = YAML.safe_load(yaml_content, permitted_classes: [Time, Date, Symbol])

    validate_yaml_structure!(data)

    ActiveRecord::Base.transaction do
      if mode == :replace
        # Удаляем все существующие паттерны
        BouncePattern.destroy_all
      end

      imported_count = 0
      updated_count = 0

      data['patterns'].each do |pattern_data|
        existing = BouncePattern.find_by(
          category: pattern_data['category'],
          pattern: pattern_data['pattern']
        )

        if existing
          existing.update!(
            active: pattern_data['active'],
            should_add_to_bounce: pattern_data['should_add_to_bounce'],
            should_stop_mailing: pattern_data['should_stop_mailing'],
            description: pattern_data['description'],
            priority: pattern_data['priority'],
            is_default: pattern_data['is_default']
          )
          updated_count += 1
        else
          BouncePattern.create!(
            category: pattern_data['category'],
            pattern: pattern_data['pattern'],
            active: pattern_data['active'],
            should_add_to_bounce: pattern_data['should_add_to_bounce'],
            should_stop_mailing: pattern_data['should_stop_mailing'],
            description: pattern_data['description'],
            priority: pattern_data['priority'] || 0,
            is_default: pattern_data['is_default'] || false
          )
          imported_count += 1
        end
      end

      # Сбрасываем кеш ErrorClassifier
      ErrorClassifier.clear_cache!

      {
        success: true,
        imported: imported_count,
        updated: updated_count,
        total: data['patterns'].size
      }
    end
  rescue Psych::SyntaxError => e
    raise ImportError, "Invalid YAML syntax: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    raise ImportError, "Validation error: #{e.message}"
  end

  private

  def self.validate_yaml_structure!(data)
    raise ImportError, "Missing 'patterns' key" unless data['patterns'].is_a?(Array)

    required_keys = %w[category pattern]
    data['patterns'].each_with_index do |pattern, index|
      required_keys.each do |key|
        raise ImportError, "Pattern ##{index + 1}: missing '#{key}' key" unless pattern.key?(key)
      end
    end
  end
end
```

---

### 3. Обновление ErrorClassifier

```ruby
# app/services/error_classifier.rb
class ErrorClassifier
  # DEPRECATED: Старые константы (будут удалены после миграции)
  # ERROR_PATTERNS = { ... }.freeze
  # NON_BOUNCE_CATEGORIES = %w[...].freeze
  # STOP_MAILING_CATEGORIES = %w[...].freeze

  class << self
    def classify(payload)
      output = extract_text(payload, :output) || ''
      details = extract_text(payload, :details) || ''
      status = extract_text(payload, :status) || ''

      full_text = "#{status} #{output} #{details}".downcase

      category = find_category(full_text)
      smtp_code = extract_smtp_code(output)

      # Получаем поведение из БД или используем дефолты
      pattern_record = matched_pattern_record(category, full_text)
      should_add_to_bounce = pattern_record&.should_add_to_bounce || default_bounce_behavior(category)
      should_stop_mailing = pattern_record&.should_stop_mailing || default_stop_behavior(category)

      {
        category: category,
        bounce_type: 'hard',
        smtp_code: smtp_code,
        message: output.presence || details.presence || status,
        should_add_to_bounce: should_add_to_bounce,
        should_stop_mailing: should_stop_mailing
      }
    end

    def clear_cache!
      @patterns_cache = nil
      @patterns_cache_expires_at = nil
    end

    private

    def find_category(text)
      patterns_hash.each do |category, patterns|
        return category.to_sym if patterns.any? { |pattern| text.include?(pattern.downcase) }
      end
      :unknown
    end

    def matched_pattern_record(category, text)
      # Находим первый подошедший паттерн для получения его настроек
      BouncePattern.active.by_category(category.to_s).ordered.find do |bp|
        text.include?(bp.pattern.downcase)
      end
    end

    def patterns_hash
      # Кешируем паттерны на 5 минут
      if @patterns_cache.nil? || @patterns_cache_expires_at < Time.current
        @patterns_cache = BouncePattern.for_classification
        @patterns_cache_expires_at = 5.minutes.from_now
      end
      @patterns_cache
    end

    def default_bounce_behavior(category)
      # Fallback если паттерн не найден в БД
      !%w[rate_limit temporary connection].include?(category.to_s)
    end

    def default_stop_behavior(category)
      # Fallback если паттерн не найден в БД
      %w[rate_limit spam_block mailbox_full temporary connection].include?(category.to_s)
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

---

### 4. Controller

```ruby
# app/controllers/dashboard/bounce_patterns_controller.rb
module Dashboard
  class BouncePatternsController < BaseController
    before_action :set_pattern, only: [:edit, :update, :destroy, :toggle_active]

    # GET /dashboard/bounce_patterns
    def index
      @category = params[:category]
      @search = params[:search]
      @show_inactive = params[:show_inactive] == 'true'

      @patterns = BouncePattern.ordered
      @patterns = @patterns.by_category(@category) if @category.present?
      @patterns = @patterns.active unless @show_inactive
      @patterns = @patterns.where('pattern ILIKE ?', "%#{@search}%") if @search.present?

      @patterns = @patterns.page(params[:page]).per(50)

      @stats = {
        total: BouncePattern.count,
        active: BouncePattern.active.count,
        by_category: BouncePattern.active.group(:category).count
      }
    end

    # GET /dashboard/bounce_patterns/new
    def new
      @pattern = BouncePattern.new
    end

    # GET /dashboard/bounce_patterns/:id/edit
    def edit
    end

    # POST /dashboard/bounce_patterns
    def create
      @pattern = BouncePattern.new(pattern_params)

      if @pattern.save
        ErrorClassifier.clear_cache!
        redirect_to dashboard_bounce_patterns_path, notice: 'Pattern created successfully'
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH /dashboard/bounce_patterns/:id
    def update
      if @pattern.update(pattern_params)
        ErrorClassifier.clear_cache!
        redirect_to dashboard_bounce_patterns_path, notice: 'Pattern updated successfully'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /dashboard/bounce_patterns/:id
    def destroy
      unless @pattern.is_default?
        @pattern.destroy
        ErrorClassifier.clear_cache!
        redirect_to dashboard_bounce_patterns_path, notice: 'Pattern deleted successfully'
      else
        redirect_to dashboard_bounce_patterns_path, alert: 'Cannot delete default pattern. Deactivate it instead.'
      end
    end

    # POST /dashboard/bounce_patterns/:id/toggle_active
    def toggle_active
      @pattern.toggle_active!
      ErrorClassifier.clear_cache!

      respond_to do |format|
        format.html { redirect_to dashboard_bounce_patterns_path, notice: "Pattern #{@pattern.active? ? 'activated' : 'deactivated'}" }
        format.json { render json: { success: true, active: @pattern.active } }
      end
    end

    # GET /dashboard/bounce_patterns/export
    def export
      yaml_content = BouncePatternYamlService.export

      send_data yaml_content,
        filename: "bounce_patterns_#{Time.current.to_i}.yml",
        type: 'application/x-yaml',
        disposition: 'attachment'
    end

    # POST /dashboard/bounce_patterns/import
    def import
      uploaded_file = params[:yaml_file]
      mode = params[:mode] || 'merge'  # merge или replace

      unless uploaded_file
        redirect_to dashboard_bounce_patterns_path, alert: 'No file selected'
        return
      end

      begin
        yaml_content = uploaded_file.read
        result = BouncePatternYamlService.import(yaml_content, mode: mode.to_sym)

        redirect_to dashboard_bounce_patterns_path,
          notice: "Import successful: #{result[:imported]} created, #{result[:updated]} updated"
      rescue BouncePatternYamlService::ImportError => e
        redirect_to dashboard_bounce_patterns_path, alert: "Import failed: #{e.message}"
      end
    end

    # POST /dashboard/bounce_patterns/reset_defaults
    def reset_defaults
      BouncePattern.reset_to_defaults!
      ErrorClassifier.clear_cache!

      redirect_to dashboard_bounce_patterns_path, notice: 'Reset to default patterns successfully'
    end

    private

    def set_pattern
      @pattern = BouncePattern.find(params[:id])
    end

    def pattern_params
      params.require(:bounce_pattern).permit(
        :category,
        :pattern,
        :active,
        :should_add_to_bounce,
        :should_stop_mailing,
        :description,
        :priority
      )
    end
  end
end
```

---

## 🎨 FRONTEND РЕАЛИЗАЦИЯ

### 1. Routes

```ruby
# config/routes.rb

Rails.application.routes.draw do
  namespace :dashboard do
    # ... existing routes ...

    resources :bounce_patterns do
      member do
        post :toggle_active
      end

      collection do
        get :export
        post :import
        post :reset_defaults
      end
    end
  end
end
```

### 2. Main View (index)

```erb
<%# app/views/dashboard/bounce_patterns/index.html.erb %>

<div class="container mx-auto px-4 py-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-3xl font-bold text-gray-900">Bounce Patterns</h1>

    <div class="flex gap-2">
      <%= link_to 'New Pattern', new_dashboard_bounce_pattern_path, class: 'btn btn-primary' %>
      <%= link_to 'Export YAML', export_dashboard_bounce_patterns_path, class: 'btn btn-secondary' %>
      <%= button_tag 'Import YAML', type: 'button', onclick: 'openImportModal()', class: 'btn btn-secondary' %>
      <%= button_tag 'Reset to Defaults', type: 'button', onclick: 'confirmReset()', class: 'btn btn-danger' %>
    </div>
  </div>

  <%# Stats Cards %>
  <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
    <div class="bg-white rounded-lg shadow p-4">
      <div class="text-sm text-gray-600">Total Patterns</div>
      <div class="text-2xl font-bold"><%= @stats[:total] %></div>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <div class="text-sm text-gray-600">Active</div>
      <div class="text-2xl font-bold text-green-600"><%= @stats[:active] %></div>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <div class="text-sm text-gray-600">Inactive</div>
      <div class="text-2xl font-bold text-gray-600"><%= @stats[:total] - @stats[:active] %></div>
    </div>
    <div class="bg-white rounded-lg shadow p-4">
      <div class="text-sm text-gray-600">Categories</div>
      <div class="text-2xl font-bold"><%= @stats[:by_category].keys.count %></div>
    </div>
  </div>

  <%# Filters %>
  <div class="bg-white rounded-lg shadow p-4 mb-6">
    <%= form_with url: dashboard_bounce_patterns_path, method: :get, class: 'flex gap-4' do |f| %>
      <div class="flex-1">
        <%= f.label :category, 'Category', class: 'block text-sm font-medium text-gray-700 mb-1' %>
        <%= f.select :category,
          options_for_select([['All Categories', '']] + BouncePattern.categories.map { |c| [c.humanize, c] }, @category),
          {}, class: 'form-select w-full' %>
      </div>

      <div class="flex-1">
        <%= f.label :search, 'Search Pattern', class: 'block text-sm font-medium text-gray-700 mb-1' %>
        <%= f.text_field :search, value: @search, placeholder: 'Search...', class: 'form-input w-full' %>
      </div>

      <div class="flex items-end">
        <%= f.label :show_inactive, class: 'flex items-center cursor-pointer' do %>
          <%= f.check_box :show_inactive, { checked: @show_inactive, class: 'mr-2' }, 'true', 'false' %>
          <span class="text-sm text-gray-700">Show Inactive</span>
        <% end %>
      </div>

      <div class="flex items-end gap-2">
        <%= f.submit 'Filter', class: 'btn btn-primary' %>
        <%= link_to 'Reset', dashboard_bounce_patterns_path, class: 'btn btn-secondary' %>
      </div>
    <% end %>
  </div>

  <%# Patterns Table %>
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Category</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Pattern</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Behavior</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Description</th>
          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @patterns.each do |pattern| %>
          <tr class="<%= 'opacity-50' unless pattern.active %>">
            <td class="px-6 py-4 whitespace-nowrap">
              <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full <%= pattern.active? ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' %>">
                <%= pattern.active? ? 'Active' : 'Inactive' %>
              </span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap">
              <span class="px-2 py-1 text-xs font-medium rounded bg-blue-100 text-blue-800">
                <%= pattern.category_human %>
              </span>
            </td>
            <td class="px-6 py-4">
              <code class="text-sm bg-gray-100 px-2 py-1 rounded"><%= pattern.pattern %></code>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm">
              <div class="flex gap-2">
                <% if pattern.should_add_to_bounce %>
                  <span class="px-2 py-1 bg-red-100 text-red-800 rounded text-xs">Bounce</span>
                <% end %>
                <% if pattern.should_stop_mailing %>
                  <span class="px-2 py-1 bg-orange-100 text-orange-800 rounded text-xs">Stop</span>
                <% end %>
              </div>
            </td>
            <td class="px-6 py-4 text-sm text-gray-600">
              <%= truncate(pattern.description, length: 50) %>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
              <div class="flex justify-end gap-2">
                <%= button_to toggle_active_dashboard_bounce_pattern_path(pattern),
                  method: :post,
                  class: "text-blue-600 hover:text-blue-900",
                  title: pattern.active? ? 'Deactivate' : 'Activate',
                  data: { turbo: false } do %>
                  <%= pattern.active? ? '⏸' : '▶' %>
                <% end %>

                <%= link_to '✏️', edit_dashboard_bounce_pattern_path(pattern), class: 'text-indigo-600 hover:text-indigo-900', title: 'Edit' %>

                <% unless pattern.is_default? %>
                  <%= button_to '🗑', dashboard_bounce_pattern_path(pattern),
                    method: :delete,
                    class: 'text-red-600 hover:text-red-900',
                    title: 'Delete',
                    data: { confirm: 'Are you sure?' } do %>
                    🗑
                  <% end %>
                <% end %>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <%# Pagination %>
  <div class="mt-6">
    <%= paginate @patterns %>
  </div>
</div>

<%# Import Modal %>
<div id="importModal" class="hidden fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
  <div class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white">
    <h3 class="text-lg font-bold mb-4">Import Bounce Patterns</h3>

    <%= form_with url: import_dashboard_bounce_patterns_path, multipart: true, class: 'space-y-4' do |f| %>
      <div>
        <%= f.label :yaml_file, 'Select YAML File', class: 'block text-sm font-medium mb-2' %>
        <%= f.file_field :yaml_file, accept: '.yml,.yaml', required: true, class: 'form-input w-full' %>
      </div>

      <div>
        <%= f.label :mode, 'Import Mode', class: 'block text-sm font-medium mb-2' %>
        <%= f.select :mode, [
          ['Merge (add new, update existing)', 'merge'],
          ['Replace (delete all, load from file)', 'replace']
        ], {}, class: 'form-select w-full' %>
      </div>

      <div class="flex justify-end gap-2">
        <%= button_tag 'Cancel', type: 'button', onclick: 'closeImportModal()', class: 'btn btn-secondary' %>
        <%= f.submit 'Import', class: 'btn btn-primary' %>
      </div>
    <% end %>
  </div>
</div>

<script>
function openImportModal() {
  document.getElementById('importModal').classList.remove('hidden');
}

function closeImportModal() {
  document.getElementById('importModal').classList.add('hidden');
}

function confirmReset() {
  if (confirm('Reset to default patterns? This will delete all custom patterns and reactivate all defaults.')) {
    fetch('<%= reset_defaults_dashboard_bounce_patterns_path %>', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    }).then(response => {
      if (response.ok) {
        window.location.reload();
      }
    });
  }
}
</script>
```

---

### 3. Form Partial

```erb
<%# app/views/dashboard/bounce_patterns/_form.html.erb %>

<%= form_with model: [:dashboard, pattern], class: 'space-y-6' do |f| %>
  <% if pattern.errors.any? %>
    <div class="rounded-md bg-red-50 p-4">
      <h3 class="text-sm font-medium text-red-800">
        <%= pluralize(pattern.errors.count, "error") %> prohibited this pattern from being saved:
      </h3>
      <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
        <% pattern.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :category, class: 'block text-sm font-medium text-gray-700 mb-2' %>
    <%= f.select :category,
      BouncePattern.categories.map { |c| [c.humanize, c] },
      {},
      class: 'form-select w-full',
      required: true %>
  </div>

  <div>
    <%= f.label :pattern, class: 'block text-sm font-medium text-gray-700 mb-2' %>
    <%= f.text_field :pattern,
      placeholder: 'e.g., rate limit, 421, spam',
      class: 'form-input w-full',
      required: true %>
    <p class="mt-1 text-sm text-gray-500">Text to search for in error messages (case-insensitive)</p>
  </div>

  <div>
    <%= f.label :description, class: 'block text-sm font-medium text-gray-700 mb-2' %>
    <%= f.text_area :description,
      rows: 3,
      placeholder: 'Optional description for this pattern',
      class: 'form-textarea w-full' %>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :should_add_to_bounce, class: 'flex items-center cursor-pointer' do %>
        <%= f.check_box :should_add_to_bounce, class: 'mr-2' %>
        <span class="text-sm font-medium text-gray-700">Add to Bounce List</span>
      <% end %>
      <p class="mt-1 text-xs text-gray-500">Mark email address as bounced</p>
    </div>

    <div>
      <%= f.label :should_stop_mailing, class: 'flex items-center cursor-pointer' do %>
        <%= f.check_box :should_stop_mailing, class: 'mr-2' %>
        <span class="text-sm font-medium text-gray-700">Stop Mailing</span>
      <% end %>
      <p class="mt-1 text-xs text-gray-500">Stop campaign when threshold exceeded</p>
    </div>
  </div>

  <div>
    <%= f.label :priority, class: 'block text-sm font-medium text-gray-700 mb-2' %>
    <%= f.number_field :priority,
      class: 'form-input w-full',
      min: 0 %>
    <p class="mt-1 text-sm text-gray-500">Lower values are checked first</p>
  </div>

  <div>
    <%= f.label :active, class: 'flex items-center cursor-pointer' do %>
      <%= f.check_box :active, class: 'mr-2' %>
      <span class="text-sm font-medium text-gray-700">Active</span>
    <% end %>
  </div>

  <div class="flex justify-end gap-2">
    <%= link_to 'Cancel', dashboard_bounce_patterns_path, class: 'btn btn-secondary' %>
    <%= f.submit class: 'btn btn-primary' %>
  </div>
<% end %>
```

---

### 4. New/Edit Views

```erb
<%# app/views/dashboard/bounce_patterns/new.html.erb %>

<div class="container mx-auto px-4 py-6 max-w-2xl">
  <h1 class="text-3xl font-bold text-gray-900 mb-6">New Bounce Pattern</h1>

  <div class="bg-white rounded-lg shadow p-6">
    <%= render 'form', pattern: @pattern %>
  </div>
</div>
```

```erb
<%# app/views/dashboard/bounce_patterns/edit.html.erb %>

<div class="container mx-auto px-4 py-6 max-w-2xl">
  <h1 class="text-3xl font-bold text-gray-900 mb-6">Edit Bounce Pattern</h1>

  <div class="bg-white rounded-lg shadow p-6">
    <%= render 'form', pattern: @pattern %>
  </div>
</div>
```

---

## 🔄 МИГРАЦИЯ ДАННЫХ

### План миграции

```bash
# 1. Создать и применить миграцию
rails db:migrate

# 2. Загрузить дефолтные паттерны из seed
rails db:seed:bounce_patterns

# 3. Проверить что все загрузилось
rails console
> BouncePattern.count  # Должно быть ~60-70 записей
> BouncePattern.group(:category).count
# => {"rate_limit"=>9, "spam_block"=>12, ...}

# 4. Тестировать ErrorClassifier
> ErrorClassifier.classify({output: "421 rate limit exceeded"})
# => {:category=>:rate_limit, :should_stop_mailing=>true, ...}

# 5. Если все OK - удалить старые константы из error_classifier.rb
# Закомментировать:
# ERROR_PATTERNS = { ... }.freeze
# NON_BOUNCE_CATEGORIES = ...
# STOP_MAILING_CATEGORIES = ...
```

### Rollback план

Если что-то пошло не так:

```bash
# 1. Вернуть старые константы в error_classifier.rb
git checkout HEAD -- services/api/app/services/error_classifier.rb

# 2. Откатить миграцию
rails db:rollback

# 3. Перезапустить приложение
docker compose restart api
```

---

## ✅ ТЕСТИРОВАНИЕ

### Тесты моделей

```ruby
# spec/models/bounce_pattern_spec.rb
require 'rails_helper'

RSpec.describe BouncePattern, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:category) }
    it { should validate_presence_of(:pattern) }
    it { should validate_uniqueness_of(:pattern).scoped_to(:category) }

    it 'validates category inclusion' do
      pattern = build(:bounce_pattern, category: 'invalid')
      expect(pattern).not_to be_valid
      expect(pattern.errors[:category]).to include('is not a valid category')
    end
  end

  describe 'scopes' do
    let!(:active_pattern) { create(:bounce_pattern, active: true) }
    let!(:inactive_pattern) { create(:bounce_pattern, active: false) }

    it 'filters active patterns' do
      expect(BouncePattern.active).to include(active_pattern)
      expect(BouncePattern.active).not_to include(inactive_pattern)
    end
  end

  describe '.for_classification' do
    before do
      create(:bounce_pattern, category: 'spam_block', pattern: 'spam', active: true)
      create(:bounce_pattern, category: 'spam_block', pattern: 'blocked', active: true)
      create(:bounce_pattern, category: 'spam_block', pattern: 'inactive', active: false)
    end

    it 'returns hash grouped by category with only active patterns' do
      result = BouncePattern.for_classification
      expect(result['spam_block']).to eq(['spam', 'blocked'])
      expect(result['spam_block']).not_to include('inactive')
    end
  end

  describe '#toggle_active!' do
    let(:pattern) { create(:bounce_pattern, active: true) }

    it 'toggles active status' do
      expect { pattern.toggle_active! }.to change { pattern.active }.from(true).to(false)
    end
  end
end
```

### Тесты сервисов

```ruby
# spec/services/bounce_pattern_yaml_service_spec.rb
require 'rails_helper'

RSpec.describe BouncePatternYamlService do
  describe '.export' do
    before do
      create(:bounce_pattern, category: 'spam_block', pattern: 'spam')
    end

    it 'exports patterns to YAML' do
      yaml = BouncePatternYamlService.export
      data = YAML.safe_load(yaml)

      expect(data['version']).to eq('1.0')
      expect(data['patterns']).to be_an(Array)
      expect(data['patterns'].first['category']).to eq('spam_block')
    end
  end

  describe '.import' do
    let(:yaml_content) do
      {
        'version' => '1.0',
        'patterns' => [
          {
            'category' => 'rate_limit',
            'pattern' => 'test pattern',
            'active' => true,
            'should_add_to_bounce' => false,
            'should_stop_mailing' => true
          }
        ]
      }.to_yaml
    end

    it 'imports patterns from YAML' do
      expect {
        BouncePatternYamlService.import(yaml_content, mode: :replace)
      }.to change { BouncePattern.count }.by(1)

      pattern = BouncePattern.last
      expect(pattern.category).to eq('rate_limit')
      expect(pattern.pattern).to eq('test pattern')
    end
  end
end
```

### Тесты контроллера

```ruby
# spec/controllers/dashboard/bounce_patterns_controller_spec.rb
require 'rails_helper'

RSpec.describe Dashboard::BouncePatternsController, type: :controller do
  describe 'GET #index' do
    it 'returns success' do
      get :index
      expect(response).to be_successful
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        bounce_pattern: {
          category: 'spam_block',
          pattern: 'new pattern',
          active: true,
          should_add_to_bounce: true,
          should_stop_mailing: false
        }
      }
    end

    it 'creates new pattern' do
      expect {
        post :create, params: valid_params
      }.to change { BouncePattern.count }.by(1)

      expect(response).to redirect_to(dashboard_bounce_patterns_path)
    end
  end
end
```

---

## ⏱️ ТАЙМЛАЙН

### Общая оценка: ~16 часов

| Этап | Задачи | Время | Статус |
|------|--------|-------|--------|
| 1 | База данных (миграция, индексы, seed) | 2ч | ⏳ Pending |
| 2 | Backend models | 1.5ч | ⏳ Pending |
| 3 | Backend services | 2ч | ⏳ Pending |
| 4 | Backend controllers | 1.5ч | ⏳ Pending |
| 5 | Frontend views | 3ч | ⏳ Pending |
| 6 | Frontend JavaScript | 1.5ч | ⏳ Pending |
| 7 | Routes & Navigation | 0.5ч | ⏳ Pending |
| 8 | Testing | 2ч | ⏳ Pending |
| 9 | Миграция данных | 1ч | ⏳ Pending |
| 10 | Документация | 1ч | ⏳ Pending |

### Порядок выполнения

```
День 1 (4-5 часов):
  ├─ Этап 1: База данных ✅
  ├─ Этап 2: Models ✅
  └─ Этап 3: Services ✅

День 2 (4-5 часов):
  ├─ Этап 4: Controllers ✅
  ├─ Этап 5: Views (начало) ⏳
  └─ ...

День 3 (4-5 часов):
  ├─ Этап 5: Views (завершение) ✅
  ├─ Этап 6: JavaScript ✅
  ├─ Этап 7: Routes ✅
  └─ Этап 8: Testing (начало) ⏳

День 4 (2-3 часа):
  ├─ Этап 8: Testing (завершение) ✅
  ├─ Этап 9: Миграция ✅
  └─ Этап 10: Документация ✅
```

---

## 📚 ДОПОЛНИТЕЛЬНЫЕ МАТЕРИАЛЫ

### Формат YAML для экспорта/импорта

```yaml
version: '1.0'
exported_at: '2026-01-13T12:00:00Z'
patterns_count: 65
patterns:
  - category: rate_limit
    pattern: rate limit
    active: true
    should_add_to_bounce: false
    should_stop_mailing: true
    description: Rate limiting errors from email providers
    priority: 0
    is_default: true

  - category: spam_block
    pattern: spam
    active: true
    should_add_to_bounce: true
    should_stop_mailing: true
    description: Spam blocks and blacklist rejections
    priority: 0
    is_default: true

  # ... остальные паттерны
```

### Пример кастомного паттерна

Если нужно добавить специфичный паттерн для провайдера:

```yaml
- category: rate_limit
  pattern: "Gmail rate limit: 450 4.2.1"
  active: true
  should_add_to_bounce: false
  should_stop_mailing: true
  description: Gmail-specific rate limit message
  priority: 1
  is_default: false
```

---

## 🎯 КРИТЕРИИ УСПЕХА

### Функциональные требования

- ✅ Можно добавлять/редактировать/удалять паттерны через UI
- ✅ Можно активировать/деактивировать паттерны
- ✅ Экспорт конфигурации в YAML работает
- ✅ Импорт конфигурации из YAML работает (merge и replace)
- ✅ Кнопка Reset to Defaults возвращает дефолтные паттерны
- ✅ ErrorClassifier использует паттерны из БД
- ✅ Изменения применяются мгновенно (с кешированием на 5 минут)

### Нефункциональные требования

- ✅ Performance: классификация ошибок < 10ms
- ✅ UI responsive и удобный
- ✅ Валидация на фронтенде и бекенде
- ✅ Тесты покрывают основной функционал
- ✅ Документация понятна и полна

---

## 📞 ВОПРОСЫ И ОТВЕТЫ

### Q: Можно ли использовать regex в паттернах?
**A:** Текущая реализация использует `text.include?(pattern)`. Для regex нужно добавить поле `is_regex: boolean` и модифицировать логику поиска.

### Q: Что если два паттерна матчатся одновременно?
**A:** Используется первый найденный паттерн (по priority, потом по created_at). Рекомендуется настраивать priority.

### Q: Как синхронизировать паттерны между серверами?
**A:** Экспортировать YAML на одном сервере, импортировать на другом. Или коммитить YAML в git и загружать через seed.

### Q: Влияет ли кеширование на мгновенное применение изменений?
**A:** Да, кеш на 5 минут. После изменений вызывается `ErrorClassifier.clear_cache!`, но изменения применятся к новым запросам. Запущенные процессы обновят кеш через 5 минут.

---

## ✅ ГОТОВНОСТЬ К СТАРТУ

**Этот документ содержит:**
- ✅ Полное описание архитектуры
- ✅ Детальную схему БД с SQL
- ✅ Полный код моделей, сервисов, контроллеров
- ✅ Полный код views с HTML/ERB
- ✅ План тестирования
- ✅ Стратегию миграции и отката
- ✅ Таймлайн с оценками

**Следующий шаг:** Начать реализацию с Этапа 1 (База данных)

---

**Дата создания:** 2026-01-13
**Автор:** Claude
**Версия:** 1.0
**Статус:** 📝 Утвержден к реализации
