#!/bin/bash
# ===========================================
# EMAIL SENDER INFRASTRUCTURE
# Production Deployment Script
# ===========================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ===========================================
# ПРОВЕРКИ
# ===========================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Запустите скрипт от root: sudo ./deploy-production.sh"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker не установлен. Установите Docker сначала."
        exit 1
    fi
    
    if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
        log_error "Docker Compose не установлен. Установите Docker Compose сначала."
        exit 1
    fi
    
    log_success "Docker и Docker Compose установлены"
}

check_files() {
    if [ ! -f "docker-compose.yml" ]; then
        log_error "Файл docker-compose.yml не найден. Запустите скрипт из корня проекта."
        exit 1
    fi
    
    if [ ! -f "config/postal.yml" ]; then
        log_error "Файл config/postal.yml не найден."
        exit 1
    fi
    
    if [ ! -f "config/nginx.conf" ]; then
        log_error "Файл config/nginx.conf не найден."
        exit 1
    fi
    
    log_success "Все необходимые файлы найдены"
}

# ===========================================
# СОЗДАНИЕ .ENV ФАЙЛА
# ===========================================

create_env_file() {
    if [ -f ".env" ]; then
        log_warning ".env файл уже существует. Пропускаю создание."
        return
    fi
    
    log_info "Создание .env файла..."
    
    if [ ! -f "env.example.txt" ]; then
        log_error "Файл env.example.txt не найден."
        exit 1
    fi
    
    cp env.example.txt .env
    
    # Генерация секретов
    log_info "Генерация секретов..."
    
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    MARIADB_PASSWORD=$(openssl rand -hex 16)
    RABBITMQ_PASSWORD=$(openssl rand -hex 16)
    SECRET_KEY_BASE=$(openssl rand -hex 32)
    POSTAL_SIGNING_KEY=$(openssl rand -hex 32)
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    
    # Замена значений в .env
    sed -i "s|POSTGRES_PASSWORD=CHANGE_ME_GENERATE_RANDOM|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|g" .env
    sed -i "s|MARIADB_PASSWORD=CHANGE_ME_GENERATE_RANDOM|MARIADB_PASSWORD=${MARIADB_PASSWORD}|g" .env
    sed -i "s|RABBITMQ_PASSWORD=CHANGE_ME_GENERATE_RANDOM|RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}|g" .env
    sed -i "s|SECRET_KEY_BASE=CHANGE_ME_GENERATE_64_HEX|SECRET_KEY_BASE=${SECRET_KEY_BASE}|g" .env
    sed -i "s|POSTAL_SIGNING_KEY=CHANGE_ME_GENERATE_64_HEX|POSTAL_SIGNING_KEY=${POSTAL_SIGNING_KEY}|g" .env
    sed -i "s|WEBHOOK_SECRET=CHANGE_ME_GENERATE_64_HEX|WEBHOOK_SECRET=${WEBHOOK_SECRET}|g" .env
    
    # Запрос недостающих значений
    if ! grep -q "^DOMAIN=" .env || grep -q "^DOMAIN=$" .env; then
        read -p "Введите домен (например, linenarrow.com): " DOMAIN
        sed -i "s|^DOMAIN=.*|DOMAIN=${DOMAIN}|g" .env
    fi
    
    if ! grep -q "^LETSENCRYPT_EMAIL=" .env || grep -q "^LETSENCRYPT_EMAIL=$" .env; then
        read -p "Введите email для Let's Encrypt: " LETSENCRYPT_EMAIL
        sed -i "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}|g" .env
    fi
    
    if ! grep -q "^ALLOWED_SENDER_DOMAINS=" .env || grep -q "^ALLOWED_SENDER_DOMAINS=$" .env; then
        read -p "Введите разрешённые домены отправителя (через запятую): " ALLOWED_SENDER_DOMAINS
        sed -i "s|^ALLOWED_SENDER_DOMAINS=.*|ALLOWED_SENDER_DOMAINS=${ALLOWED_SENDER_DOMAINS}|g" .env
    fi
    
    if ! grep -q "^DASHBOARD_PASSWORD=" .env || grep -q "^DASHBOARD_PASSWORD=CHANGE_ME" .env; then
        read -sp "Введите пароль для Dashboard: " DASHBOARD_PASSWORD
        echo ""
        sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}|g" .env
    fi
    
    if ! grep -q "^SIDEKIQ_WEB_PASSWORD=" .env || grep -q "^SIDEKIQ_WEB_PASSWORD=CHANGE_ME" .env; then
        read -sp "Введите пароль для Sidekiq Web UI: " SIDEKIQ_WEB_PASSWORD
        echo ""
        sed -i "s|^SIDEKIQ_WEB_PASSWORD=.*|SIDEKIQ_WEB_PASSWORD=${SIDEKIQ_WEB_PASSWORD}|g" .env
    fi
    
    chmod 600 .env
    log_success ".env файл создан"
}

# ===========================================
# СОЗДАНИЕ .HTPASSWD ФАЙЛА
# ===========================================

create_htpasswd() {
    if [ -f "config/htpasswd" ]; then
        log_warning "Файл config/htpasswd уже существует. Пропускаю создание."
        return
    fi
    
    log_info "Создание .htpasswd файла..."
    
    if [ -f "scripts/create-htpasswd.sh" ]; then
        bash scripts/create-htpasswd.sh
    else
        log_warning "Скрипт create-htpasswd.sh не найден. Создаю вручную..."
        read -p "Введите имя пользователя для Basic Auth [admin]: " HTPASSWD_USER
        HTPASSWD_USER=${HTPASSWD_USER:-admin}
        read -sp "Введите пароль для Basic Auth: " HTPASSWD_PASS
        echo ""
        
        mkdir -p config
        if command -v htpasswd &> /dev/null; then
            htpasswd -b -c config/htpasswd "$HTPASSWD_USER" "$HTPASSWD_PASS"
        else
            HASH=$(openssl passwd -apr1 "$HTPASSWD_PASS")
            echo "$HTPASSWD_USER:$HASH" > config/htpasswd
        fi
        chmod 600 config/htpasswd
    fi
    
    log_success ".htpasswd файл создан"
}

# ===========================================
# ЗАПУСК СЕРВИСОВ
# ===========================================

start_services() {
    log_info "Запуск сервисов..."
    
    # Запуск баз данных
    log_info "Запуск баз данных..."
    docker compose up -d postgres redis mariadb rabbitmq
    
    log_info "Ожидание инициализации баз данных (60 сек)..."
    sleep 60
    
    # Проверка готовности баз данных
    log_info "Проверка готовности баз данных..."
    until docker compose exec -T postgres pg_isready -U email_sender &> /dev/null; do
        log_info "PostgreSQL ещё не готов, жду..."
        sleep 5
    done
    
    until docker compose exec -T redis redis-cli ping &> /dev/null; do
        log_info "Redis ещё не готов, жду..."
        sleep 5
    done
    
    log_success "Базы данных готовы"
    
    # Инициализация Postal (если первый запуск)
    log_info "Инициализация Postal..."
    docker compose run --rm postal postal initialize-db || true
    docker compose run --rm postal postal make-user || true
    
    # Запуск всех сервисов
    log_info "Запуск всех сервисов..."
    docker compose up -d
    
    log_info "Ожидание готовности сервисов (30 сек)..."
    sleep 30
    
    log_success "Сервисы запущены"
}

# ===========================================
# SSL СЕРТИФИКАТ
# ===========================================

setup_ssl() {
    log_info "Настройка SSL сертификата..."
    
    # Получение домена из .env
    DOMAIN=$(grep "^DOMAIN=" .env | cut -d '=' -f2)
    LETSENCRYPT_EMAIL=$(grep "^LETSENCRYPT_EMAIL=" .env | cut -d '=' -f2)
    
    if [ -z "$DOMAIN" ]; then
        log_error "DOMAIN не установлен в .env файле"
        return 1
    fi
    
    log_info "Получение SSL сертификата для $DOMAIN..."
    
    # Проверка, существует ли уже сертификат
    if docker compose exec -T nginx test -f "/etc/nginx/certs/live/${DOMAIN}/fullchain.pem" 2>/dev/null; then
        log_warning "SSL сертификат уже существует. Пропускаю получение."
        return 0
    fi
    
    # Получение сертификата
    docker compose run --rm certbot certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$LETSENCRYPT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" || {
        log_warning "Не удалось получить SSL сертификат. Продолжаю без SSL."
        return 0
    }
    
    # Перезапуск nginx
    docker compose restart nginx
    
    log_success "SSL сертификат настроен"
}

# ===========================================
# ПРОВЕРКА РАБОТОСПОСОБНОСТИ
# ===========================================

check_health() {
    log_info "Проверка работоспособности сервисов..."
    
    # Проверка статуса контейнеров
    log_info "Статус контейнеров:"
    docker compose ps
    
    # Проверка health endpoints
    log_info "Проверка health endpoints..."
    
    DOMAIN=$(grep "^DOMAIN=" .env | cut -d '=' -f2)
    
    # Попытка проверить через HTTP (если SSL ещё не настроен)
    if curl -f -s "http://localhost/api/v1/health" > /dev/null 2>&1; then
        log_success "API доступен через HTTP"
    elif curl -f -s -k "https://localhost/api/v1/health" > /dev/null 2>&1; then
        log_success "API доступен через HTTPS"
    else
        log_warning "API недоступен. Проверьте логи: docker compose logs api"
    fi
    
    log_success "Проверка завершена"
}

# ===========================================
# ИНФОРМАЦИЯ
# ===========================================

show_summary() {
    echo ""
    echo "=========================================="
    echo -e "  ${GREEN}Развертывание завершено!${NC}"
    echo "=========================================="
    echo ""
    
    DOMAIN=$(grep "^DOMAIN=" .env | cut -d '=' -f2)
    
    echo "Информация о сервере:"
    echo "  Домен:     https://${DOMAIN}"
    echo "  API:       https://${DOMAIN}/api/v1/"
    echo "  Tracking:  https://${DOMAIN}/track/"
    echo "  Postal:    https://${DOMAIN}/postal/"
    echo "  Sidekiq:   https://${DOMAIN}/sidekiq/"
    echo ""
    echo "Полезные команды:"
    echo "  docker compose ps          - статус сервисов"
    echo "  docker compose logs -f     - просмотр логов"
    echo "  docker compose restart     - перезапуск сервисов"
    echo ""
    echo "Для создания API ключа выполните:"
    echo "  docker compose exec api rails runner \"key = ApiKey.generate(name: 'Production'); puts key.raw_key\""
    echo ""
}

# ===========================================
# MAIN
# ===========================================

main() {
    echo ""
    echo "=========================================="
    echo "  Production Deployment Script"
    echo "=========================================="
    echo ""
    
    check_root
    check_docker
    check_files
    
    create_env_file
    create_htpasswd
    
    start_services
    setup_ssl
    
    check_health
    show_summary
}

main "$@"

