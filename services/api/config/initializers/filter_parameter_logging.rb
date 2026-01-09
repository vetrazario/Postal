# Фильтрация конфиденциальных данных в логах Rails
# Все перечисленные параметры будут заменены на [FILTERED] в логах

Rails.application.config.filter_parameters += [
  # ========================================
  # ПАРАМЕТРЫ ИЗ ЭМАИЛ КОНТРОЛЛЕРОВ
  # ========================================
  
  # EmailsController & BatchesController
  :email,
  :recipient,
  :from_email,
  :to,
  :from_name,
  :subject,
  :template_id,
  :campaign_id,
  :message_id,
  :recipient_id,
  :affiliate_id,
  
  # Вложенные объекты
  :tracking,
  :variables,
  
  # ========================================
  # SMTP КОНТРОЛЛЕР (КРИТИЧНО!)
  # ========================================
  
  # Верхний уровень
  :envelope,
  :message,
  :raw,
  
  # Ключи внутри envelope
  'envelope/from',
  'envelope/to',
  
  # Ключи внутри message
  'message/from',
  'message/to',
  'message/cc',
  'message/subject',
  'message/text',
  'message/html',
  'message/headers',
  
  # ========================================
  # АУТЕНТИФИКАЦИЯ И СЕКРЕТЫ
  # ========================================
  :password,
  :secret,
  :token,
  :api_key,
  :smtp_relay_key,
  :smtp_relay_api_key,
  :webhook_secret,
  :webhook_key,
  :private_key,
  :public_key,
  :signing_key,
  
  # ========================================
  # ДАННЫЕ ШАБЛОНОВ (могут содержать PII)
  # ========================================
  :html_body,
  :text_body,
  :plain_content,
  :html_content,
  
  # ========================================
  # ВЛОЖЕННЫЕ СТРУКТУРЫ ИЗ JSON
  # ========================================
  
  # SMTP credentials (dashboard)
  'smtp_credentials/password',
  'smtp_credentials/username',
  'smtp_credentials/host',
  
  # Webhook endpoints
  'webhook_endpoint/secret',
  'webhook_endpoint/url',
  
  # Message data
  'message/variables',
  'message/body',
  'message/plain',
  
  # ========================================
  # HTTP ЗАГОЛОВКИ (request.headers)
  # ========================================
  # Rails не фильтрует заголовки по умолчанию!
  # Эти значения будут фильтроваться если попадут в params
  
  'HTTP_AUTHORIZATION',
  'HTTP_X_API_KEY',
  'HTTP_X_SMTP_RELAY_KEY',
  'HTTP_X_WEBHOOK_SECRET',
  'HTTP_X_SIGNATURE'
]
