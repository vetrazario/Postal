# ===========================================
# EMAIL SENDER INFRASTRUCTURE
# Makefile
# ===========================================

.PHONY: help install start stop restart logs status build test clean backup

# Цвета для вывода
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# ===========================================
# HELP
# ===========================================

help: ## Показать справку
	@echo ""
	@echo "Email Sender Infrastructure - Команды"
	@echo "======================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

# ===========================================
# INSTALLATION
# ===========================================

install: ## Первоначальная установка
	@echo "$(GREEN)Начинаем установку...$(NC)"
	@./scripts/install.sh

setup-env: ## Создать .env из примера
	@if [ ! -f .env ]; then \
		cp env.example.txt .env; \
		echo "$(GREEN).env файл создан. Отредактируйте его!$(NC)"; \
	else \
		echo "$(YELLOW).env уже существует$(NC)"; \
	fi

generate-secrets: ## Сгенерировать секреты
	@echo "POSTGRES_PASSWORD=$$(openssl rand -hex 16)"
	@echo "MARIADB_PASSWORD=$$(openssl rand -hex 16)"
	@echo "RABBITMQ_PASSWORD=$$(openssl rand -hex 16)"
	@echo "SECRET_KEY_BASE=$$(openssl rand -hex 32)"
	@echo "API_KEY=$$(openssl rand -hex 24)"
	@echo "POSTAL_SIGNING_KEY=$$(openssl rand -hex 32)"
	@echo "WEBHOOK_SECRET=$$(openssl rand -hex 32)"

# ===========================================
# DOCKER COMPOSE
# ===========================================

build: ## Собрать Docker образы
	@echo "$(GREEN)Сборка образов...$(NC)"
	docker compose build

start: ## Запустить все сервисы
	@echo "$(GREEN)Запуск сервисов...$(NC)"
	docker compose up -d
	@echo "$(GREEN)Сервисы запущены!$(NC)"
	@make status

stop: ## Остановить все сервисы
	@echo "$(YELLOW)Остановка сервисов...$(NC)"
	docker compose down

restart: ## Перезапустить все сервисы
	@echo "$(YELLOW)Перезапуск сервисов...$(NC)"
	docker compose restart

restart-api: ## Перезапустить только API и Sidekiq
	docker compose restart api sidekiq

status: ## Показать статус сервисов
	@echo ""
	@echo "Статус сервисов:"
	@echo "================"
	@docker compose ps
	@echo ""

logs: ## Показать логи (все сервисы)
	docker compose logs -f --tail=100

logs-api: ## Показать логи API
	docker compose logs -f api --tail=100

logs-sidekiq: ## Показать логи Sidekiq
	docker compose logs -f sidekiq --tail=100

logs-postal: ## Показать логи Postal
	docker compose logs -f postal --tail=100

# ===========================================
# DEVELOPMENT
# ===========================================

shell-api: ## Открыть shell в API контейнере
	docker compose exec api bash

shell-postgres: ## Открыть psql
	docker compose exec postgres psql -U email_sender -d email_sender

shell-redis: ## Открыть redis-cli
	docker compose exec redis redis-cli

console: ## Открыть Rails console
	docker compose exec api rails console

# ===========================================
# TESTING
# ===========================================

test: ## Запустить тесты
	docker compose exec api bundle exec rspec

test-api: ## Запустить тесты API
	docker compose exec api bundle exec rspec spec/controllers

lint: ## Запустить линтер
	docker compose exec api bundle exec rubocop

# ===========================================
# DATABASE
# ===========================================

db-migrate: ## Выполнить миграции
	docker compose exec api rails db:migrate

db-seed: ## Заполнить тестовыми данными
	docker compose exec api rails db:seed

db-reset: ## Сбросить и пересоздать БД
	@echo "$(RED)ВНИМАНИЕ: Это удалит все данные!$(NC)"
	@read -p "Продолжить? [y/N] " confirm && [ "$$confirm" = "y" ]
	docker compose exec api rails db:drop db:create db:migrate

# ===========================================
# MAINTENANCE
# ===========================================

backup: ## Создать бэкап
	@echo "$(GREEN)Создание бэкапа...$(NC)"
	@./scripts/backup.sh

cleanup-logs: ## Очистить старые логи
	docker compose exec api rails runner "EmailLog.where('created_at < ?', 30.days.ago).delete_all"
	docker compose exec api rails runner "TrackingEvent.where('created_at < ?', 90.days.ago).delete_all"

health: ## Проверить здоровье сервисов
	@echo "Проверка API..."
	@curl -s http://localhost/api/v1/health | jq . || echo "$(RED)API недоступен$(NC)"
	@echo ""
	@echo "Проверка Sidekiq..."
	@docker compose exec api rails runner "puts Sidekiq::Stats.new.to_json" | jq . || echo "$(RED)Sidekiq проблемы$(NC)"

# ===========================================
# SSL
# ===========================================

ssl-init: ## Получить SSL сертификат
	docker compose run --rm certbot certbot certonly \
		--webroot \
		--webroot-path=/var/www/certbot \
		--email $${LETSENCRYPT_EMAIL} \
		--agree-tos \
		--no-eff-email \
		-d $${DOMAIN}
	docker compose restart nginx

ssl-renew: ## Обновить SSL сертификат
	docker compose run --rm certbot certbot renew
	docker compose restart nginx

# ===========================================
# POSTAL
# ===========================================

postal-init: ## Инициализировать Postal
	docker compose run --rm postal postal initialize
	docker compose run --rm postal postal make-user

postal-dkim: ## Показать DKIM запись
	docker compose exec postal postal default-dkim-record

# ===========================================
# CLEANUP
# ===========================================

clean: ## Удалить все контейнеры и volumes
	@echo "$(RED)ВНИМАНИЕ: Это удалит ВСЕ данные!$(NC)"
	@read -p "Продолжить? [y/N] " confirm && [ "$$confirm" = "y" ]
	docker compose down -v
	docker system prune -f

# ===========================================
# INFO
# ===========================================

info: ## Показать информацию о системе
	@echo ""
	@echo "Email Sender Infrastructure"
	@echo "==========================="
	@echo ""
	@echo "Domain: $${DOMAIN:-not set}"
	@echo "Environment: $${RAILS_ENV:-production}"
	@echo ""
	@echo "Endpoints:"
	@echo "  API:      https://$${DOMAIN:-localhost}/api/v1/"
	@echo "  Tracking: https://$${DOMAIN:-localhost}/track/"
	@echo "  Postal:   https://$${DOMAIN:-localhost}/postal/"
	@echo ""

# ===========================================
# TESTING
# ===========================================

test: ## Запустить все тесты
	@echo "$(GREEN)Запуск тестов...$(NC)"
	@make test-unit
	@make test-e2e

test-unit: ## Запустить unit тесты
	@echo "$(GREEN)Запуск unit тестов...$(NC)"
	docker compose exec api bundle exec rspec

test-e2e: ## Запустить E2E тесты
	@echo "$(GREEN)Запуск E2E тестов...$(NC)"
	@./tests/e2e/run_tests.sh

test-e2e-python: ## Запустить E2E тесты (Python)
	@echo "$(GREEN)Запуск E2E тестов (Python)...$(NC)"
	@cd tests/e2e && pip install -r requirements.txt && pytest -v test_e2e.py

test-e2e-docker: ## Запустить E2E тесты в Docker
	@echo "$(GREEN)Запуск E2E тестов в Docker...$(NC)"
	docker compose -f tests/e2e/docker-compose.test.yml up --build --abort-on-container-exit

test-security: ## Запустить security тесты
	@echo "$(GREEN)Запуск security тестов...$(NC)"
	@./tests/e2e/run_tests.sh | grep -E "(PASS|FAIL).*[Ss]ecurity"

# ===========================================
# VALIDATION
# ===========================================

validate: ## Проверить конфигурацию
	@echo "$(GREEN)Проверка конфигурации...$(NC)"
	@make validate-env
	@make validate-nginx
	@make validate-compose

validate-env: ## Проверить переменные окружения
	@echo "Проверка .env файла..."
	@if [ -f .env ]; then \
		echo "$(GREEN).env файл существует$(NC)"; \
	else \
		echo "$(RED).env файл не найден!$(NC)"; \
		exit 1; \
	fi

validate-nginx: ## Проверить конфигурацию nginx
	@echo "Проверка nginx конфигурации..."
	docker compose exec nginx nginx -t

validate-compose: ## Проверить docker-compose
	@echo "Проверка docker-compose..."
	docker compose config --quiet && echo "$(GREEN)docker-compose.yml валиден$(NC)"

