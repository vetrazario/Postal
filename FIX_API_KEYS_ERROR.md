# Fix для ошибки 500 при открытии API Keys

## Проблема
При открытии раздела Settings и попытке нажать на кнопку "Manage API Keys" возникала ошибка 500.

## Причина
В базе данных отсутствовали таблицы `smtp_credentials` и `webhook_endpoints`, хотя миграции для них существуют (006, 007, 008). Когда view пытался вызвать `SmtpCredential.count` и `WebhookEndpoint.count`, это вызывало ошибку.

## Решение

### 1. Добавлена обработка ошибок в view (уже сделано)
В файле `/services/api/app/views/dashboard/settings/show.html.erb` добавлена обработка ошибок:
```ruby
<%= ApiKey.count rescue 0 %>
<%= SmtpCredential.count rescue 0 %>
<%= WebhookEndpoint.count rescue 0 %>
```

Теперь, даже если таблицы не существуют, страница Settings откроется без ошибки 500 и покажет 0 вместо количества записей.

### 2. Запуск недостающих миграций (необходимо выполнить)

Чтобы создать отсутствующие таблицы, запустите скрипт:

```bash
./run-migrations.sh
```

Или вручную:

```bash
docker compose exec api bundle exec rails db:migrate
```

Это создаст следующие таблицы:
- `smtp_credentials` (миграция 006) - учетные данные SMTP
- `webhook_endpoints` (миграция 007) - конечные точки webhooks
- `webhook_logs` (миграция 008) - логи webhooks

## Проверка

После применения миграций:
1. Откройте страницу Settings в браузере
2. Вы должны увидеть правильное количество API Keys, SMTP Credentials и Webhooks
3. Кнопка "Manage API Keys" должна работать без ошибок

## Файлы, которые были изменены
- `/services/api/app/views/dashboard/settings/show.html.erb` - добавлена обработка ошибок

## Миграции, которые нужно применить
- `006_create_smtp_credentials.rb`
- `007_create_webhook_endpoints.rb`
- `008_create_webhook_logs.rb`
