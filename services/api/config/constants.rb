# frozen_string_literal: true

# Константы конфигурации для всех сервисов
# Все магические числа вынесены в одно место для удобного управления

module Constants
  # ===== Rate Limiting =====
  SMTP_RATE_LIMIT = 100        # SMTP запросов в минуту
  SMTP_RATE_WINDOW = 60         # Окно rate limiting (секунды)
  MAX_AUTH_FAILURES = 5        # Максимальное количество неудачных попыток аутентификации
  AUTH_BLOCK_DURATION = 300     # Длительность блокировки после неудачных попыток (секунды)

  # ===== Batch Limits =====
  MAX_BATCH_SIZE = 100          # Максимальное количество писем в batch запросе

  # ===== Email Limits =====
  MAX_EMAIL_BODY_SIZE = 14680064  # Максимальный размер тела email (14MB)

  # ===== Webhook Configuration =====
  WEBHOOK_TIMEOUT = 30         # Timeout для webhook запросов (секунды)
  WEBHOOK_RETRY_ATTEMPTS = 5  # Количество попыток повтора для webhook

  # ===== SMTP Relay Configuration =====
  DEFAULT_SMTP_RELAY_PORT = 2587    # Порт SMTP Relay по умолчанию

  # ===== Dashboard Configuration =====
  DASHBOARD_LOGIN_RATE_LIMIT = 5      # Попыток логина в минуту для dashboard

  # ===== Cache Expiration =====
  CACHE_EXPIRATION = 5.minutes     # Время истечения кеша для rate limiting

  # ===== Timeout Values =====
  DATABASE_TIMEOUT = 5              # Timeout для запросов к БД (секунды)
  REDIS_TIMEOUT = 5               # Timeout для запросов к Redis (секунды)
  API_TIMEOUT = 10                # Timeout для внешних API запросов (секунды)

  # ===== Bounce Handling =====
  BOUNCE_HARDBLOCK_THRESHOLD = 3   # После скольких hard bounce блокируется email навсегда
  SOFT_BOUNCE_RESET_DAYS = 7       # Через сколько дней сбрасывается счетчик soft bounces

  # ===== Sidekiq Configuration =====
  DEFAULT_SIDEKIQ_CONCURRENCY = 5    # Количество воркеров Sidekiq по умолчанию
  MAX_SIDEKIQ_CONCURRENCY = 50        # Максимальное количество воркеров Sidekiq

  # ===== Logging Configuration =====
  LOG_LEVELS = %w[debug info warn error fatal].freeze
  DEFAULT_LOG_LEVEL = 'info'

  # ===== HTTP Status Codes =====
  HTTP_OK = 200
  HTTP_CREATED = 201
  HTTP_BAD_REQUEST = 400
  HTTP_UNAUTHORIZED = 401
  HTTP_FORBIDDEN = 403
  HTTP_NOT_FOUND = 404
  HTTP_UNPROCESSABLE_ENTITY = 422
  HTTP_TOO_MANY_REQUESTS = 429
  HTTP_INTERNAL_SERVER_ERROR = 500

  # ===== Email Statuses =====
  EMAIL_STATUS_QUEUED = 'queued'
  EMAIL_STATUS_PROCESSING = 'processing'
  EMAIL_STATUS_SENT = 'sent'
  EMAIL_STATUS_DELIVERED = 'delivered'
  EMAIL_STATUS_BOUNCED = 'bounced'
  EMAIL_STATUS_FAILED = 'failed'
  EMAIL_STATUS_COMPLAINED = 'complained'
  EMAIL_STATUS_THROTTLED = 'throttled'

  ALL_EMAIL_STATUSES = [
    EMAIL_STATUS_QUEUED,
    EMAIL_STATUS_PROCESSING,
    EMAIL_STATUS_SENT,
    EMAIL_STATUS_DELIVERED,
    EMAIL_STATUS_BOUNCED,
    EMAIL_STATUS_FAILED,
    EMAIL_STATUS_COMPLAINED,
    EMAIL_STATUS_THROTTLED
  ].freeze

  # ===== Bounce Categories =====
  BOUNCE_CATEGORY_USER_NOT_FOUND = 'user_not_found'
  BOUNCE_CATEGORY_SPAM_BLOCK = 'spam_block'
  BOUNCE_CATEGORY_MAILBOX_FULL = 'mailbox_full'
  BOUNCE_CATEGORY_AUTHENTICATION = 'authentication'
  BOUNCE_CATEGORY_RATE_LIMIT = 'rate_limit'
  BOUNCE_CATEGORY_TEMPORARY = 'temporary'
  BOUNCE_CATEGORY_CONNECTION = 'connection'
  BOUNCE_CATEGORY_UNKNOWN = 'unknown'

  ALL_BOUNCE_CATEGORIES = [
    BOUNCE_CATEGORY_USER_NOT_FOUND,
    BOUNCE_CATEGORY_SPAM_BLOCK,
    BOUNCE_CATEGORY_MAILBOX_FULL,
    BOUNCE_CATEGORY_AUTHENTICATION,
    BOUNCE_CATEGORY_RATE_LIMIT,
    BOUNCE_CATEGORY_TEMPORARY,
    BOUNCE_CATEGORY_CONNECTION,
    BOUNCE_CATEGORY_UNKNOWN
  ].freeze

  # ===== Event Types =====
  EVENT_TYPE_OPEN = 'open'
  EVENT_TYPE_CLICK = 'click'
  EVENT_TYPE_DELIVERED = 'delivered'
  EVENT_TYPE_BOUNCE = 'bounce'
  EVENT_TYPE_COMPLAINT = 'complaint'

  ALL_EVENT_TYPES = [
    EVENT_TYPE_OPEN,
    EVENT_TYPE_CLICK,
    EVENT_TYPE_DELIVERED,
    EVENT_TYPE_BOUNCE,
    EVENT_TYPE_COMPLAINT
  ].freeze

  # ===== Encryption =====
  SALT_LENGTH = 32            # Длина соли для хеширования (байт)
  TOKEN_LENGTH = 24            # Длина токена для API ключей (байт)

  # ===== Pagination =====
  DEFAULT_PAGE_SIZE = 25       # Количество элементов на странице по умолчанию
  MAX_PAGE_SIZE = 100          # Максимальное количество элементов на странице
end
