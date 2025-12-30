# ПЛАН ИСПРАВЛЕНИЯ POSTAL

## Выявленные проблемы

### ✅ ПРОБЛЕМА #1: htpasswd путь
- **Найдено**: `/etc/nginx/htpasswd` в конфиге
- **Нужно**: `/etc/nginx/.htpasswd` (как в docker-compose)
- **Где**: строка 157 в config/nginx.conf

### ✅ ПРОБЛЕМА #2: X-Forwarded-Host вызывает 403
- **Доказано тестами**: Postal возвращает 403 при `X-Forwarded-Host: postal.linenarrow.com`
- **Без этого заголовка**: Postal возвращает 302 (работает!)
- **Решение**: НЕ отправлять X-Forwarded-Host

### ✅ ПРОБЛЕМА #3: proxy_redirect не применяется
- **Найдено**: Есть в конфиге но Postal всё равно редиректит на linenarrow.com
- **Причина**: Postal настроен на POSTAL_WEB_HOST=linenarrow.com
- **Решение**: Изменить на postal.linenarrow.com

## ПРАВИЛЬНЫЕ ИСПРАВЛЕНИЯ

1. Исправить htpasswd путь (только для /postal/ location)
2. УБРАТЬ X-Forwarded-Host из postal subdomain
3. Изменить POSTAL_WEB_HOST на postal.linenarrow.com
4. Обновить RAILS_DEVELOPMENT_HOSTS для postal.linenarrow.com

## ТЕСТ после исправлений

```bash
# Должен вернуть 302 на postal.linenarrow.com/login
curl -I https://postal.linenarrow.com
```
