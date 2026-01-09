# Верификация подписей webhook'ов от Postal

## Обзор

Все webhook'и от Postal должны быть подписаны с использованием RSA-SHA256. Это предотвращает подделку событий доставки, bounced, complained и других критических событий.

## Как это работает

1. **Postal отправляет webhook** с заголовком `X-Postal-Signature`
2. **Rails декодирует подпись** из Base64
3. **Rails читает публичный ключ** из `/config/postal_public.key`
4. **Rails проверяет подпись** используя `OpenSSL::PKey::RSA.verify()` с SHA256
5. **Если подпись валидна** → webhook обрабатывается
6. **Если подпись невалидна** → возвращается 401 Unauthorized

## Формат подписи

Postal отправляет подпись в заголовке `X-Postal-Signature` в одном из форматов:

- `sha256=<base64_signature>` (рекомендуемый формат)
- `<base64_signature>` (простой Base64)

Код автоматически обрабатывает оба формата.

## Настройка

### Шаг 1: Получить Public Key из Postal

#### Вариант А: Через Postal Web UI (РЕКОМЕНДУЕТСЯ)

1. Откройте Postal Web UI: `https://linenarrow.com/postal/`
2. Перейдите: **Organization** → **Server** → **Credentials**
3. Найдите раздел **Webhook Credentials** или создайте новый:
   - Type: Webhook
   - Name: Webhook Signing Key
4. Скопируйте **Public Key** (PEM формат)
5. Сохраните в файл на сервере:

```bash
cd /opt/email-sender
cat > config/postal_public.key << 'EOF'
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
(вставьте скопированный ключ)
-----END PUBLIC KEY-----
EOF

chmod 644 config/postal_public.key
```

#### Вариант Б: Через скрипт

```bash
cd /opt/email-sender
./scripts/get-postal-public-key.sh
```

Скрипт предоставит пошаговые инструкции.

#### Вариант В: Через Postal CLI

```bash
docker compose exec postal postal make-webhook-credential
```

Это создаст новый ключ pair и покажет public key.

### Шаг 2: Перезапустить API

```bash
docker compose build api
docker compose restart api
```

### Шаг 3: Проверить загрузку ключа

```bash
docker compose logs api --tail=30 | grep -i "public key\|signature"
```

**Ожидаемые сообщения:**
- ✅ `Postal public key loaded successfully from /config/postal_public.key`
- ❌ `Postal public key file not found` (если файла нет)

## Тестирование

### Автоматическое тестирование

```bash
cd /opt/email-sender
./scripts/test-webhook-signature.sh
```

Скрипт проверит:
1. Существование файла public key
2. Формат ключа (PEM)
3. Доступность API
4. Отклонение поддельных webhook'ов

### Ручное тестирование

#### Тест 1: Отправить тестовый email

```bash
curl -X POST https://linenarrow.com/api/v1/send \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient": "test@example.com",
    "from_name": "Test",
    "from_email": "noreply@linenarrow.com",
    "subject": "Webhook Test",
    "variables": {},
    "template_id": "welcome",
    "tracking": {"campaign_id": "test", "message_id": "test_001"}
  }'
```

После отправки Postal отправит webhook с правильной подписью.

#### Тест 2: Симулировать поддельный webhook

```bash
curl -X POST https://linenarrow.com/api/v1/webhook \
  -H "Content-Type: application/json" \
  -H "X-Postal-Signature: fake_invalid_signature" \
  -d '{
    "event": "MessageDelivered",
    "payload": {"message": {"id": "fake"}}
  }'
```

**Ожидаемый результат:** `401 Unauthorized`

### Проверка логов

```bash
# Посмотреть логи верификации
docker compose logs api --tail=50 | grep -i "signature\|webhook\|verification"

# Ожидаемые сообщения:
# - "Webhook verification attempt from <IP>"
# - "Webhook signature verified successfully" (для валидных)
# - "Invalid webhook signature" (для поддельных)
```

## Отключение верификации (только для тестирования!)

⚠️ **НЕ ИСПОЛЬЗОВАТЬ В PRODUCTION!**

Для временного отключения верификации (например, для отладки):

```bash
# В .env файле или через docker-compose.yml
SKIP_POSTAL_WEBHOOK_VERIFICATION=true

# Перезапустить API
docker compose restart api
```

После отключения в логах будет:
```
Webhook signature verification SKIPPED (testing mode) from <IP>
```

## Устранение проблем

### Проблема 1: Public key не загружен

**Симптом:** `Postal public key file not found: /config/postal_public.key`

**Решение:**
```bash
# Проверить существование файла
ls -la config/postal_public.key

# Проверить путь в docker-compose.yml
grep POSTAL_WEBHOOK_PUBLIC_KEY docker-compose.yml

# Проверить права доступа
stat config/postal_public.key
# Должно быть: -rw-r--r-- (644)
```

### Проблема 2: Ошибка валидации подписи

**Симптом:** `Invalid webhook signature from <IP> - signature verification failed`

**Решение:**
1. Убедитесь что public key соответствует signing key в Postal
2. Проверьте формат ключа (должен быть PEM RSA):
   ```bash
   head -1 config/postal_public.key
   # Должен начинаться с: -----BEGIN PUBLIC KEY-----
   ```
3. Проверьте что Postal использует ту же версию ключа
4. Проверьте логи Postal для получения правильного public key

### Проблема 3: Все webhook'и отклоняются

**Симптом:** Все webhook'и возвращают 401

**Решение:**
1. Временно включите режим тестирования для диагностики:
   ```bash
   export SKIP_POSTAL_WEBHOOK_VERIFICATION=true
   docker compose restart api
   ```
2. Проверьте логи Postal для получения правильного public key
3. Убедитесь что формат подписи правильный (может быть `sha256=...`)

### Проблема 4: Ошибка декодирования Base64

**Симптом:** `Signature verification error: ArgumentError`

**Решение:**
1. Проверьте формат заголовка `X-Postal-Signature`
2. Убедитесь что подпись в Base64 формате
3. Проверьте что нет лишних пробелов или символов

## Безопасность

### Важные моменты

1. **Никогда не коммитьте private key** в git
2. **Храните public key** в безопасном месте
3. **Регулярно проверяйте** что верификация работает
4. **Мониторьте логи** на подозрительные попытки

### Рекомендации

- Используйте отдельный ключ для каждого окружения (dev/staging/prod)
- Регулярно ротируйте ключи (раз в год)
- Логируйте все попытки верификации для аудита
- Настройте алерты на множественные неудачные попытки

## Связанные файлы

- `services/api/app/controllers/api/v1/webhooks_controller.rb` - основной код верификации
- `config/postal_public.key` - публичный ключ Postal
- `scripts/get-postal-public-key.sh` - скрипт для получения ключа
- `scripts/test-webhook-signature.sh` - скрипт для тестирования
- `docker-compose.yml` - конфигурация переменных окружения
