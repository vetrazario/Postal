#!/bin/bash
# ===========================================
# EMAIL SENDER INFRASTRUCTURE
# Installation Script
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
        log_error "Запустите скрипт от root: sudo ./install.sh"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Не удалось определить ОС"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "22.04" ]; then
        log_warning "Рекомендуется Ubuntu 22.04. Текущая ОС: $PRETTY_NAME"
        read -p "Продолжить? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# ===========================================
# УСТАНОВКА ЗАВИСИМОСТЕЙ
# ===========================================

install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker уже установлен: $(docker --version)"
        return
    fi
    
    log_info "Установка Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_success "Docker установлен"
}

install_docker_compose() {
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        log_success "Docker Compose уже установлен"
        return
    fi
    
    log_info "Установка Docker Compose..."
    apt-get update
    apt-get install -y docker-compose-plugin
    log_success "Docker Compose установлен"
}

install_dependencies() {
    log_info "Установка зависимостей..."
    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        htop \
        nano \
        ufw \
        fail2ban \
        jq \
        openssl
    log_success "Зависимости установлены"
}

# ===========================================
# НАСТРОЙКА БЕЗОПАСНОСТИ
# ===========================================

setup_firewall() {
    log_info "Настройка firewall..."
    
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp    # SSH
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS
    ufw allow 25/tcp    # SMTP
    
    ufw --force enable
    log_success "Firewall настроен"
}

setup_fail2ban() {
    log_info "Настройка fail2ban..."
    
    systemctl enable fail2ban
    systemctl start fail2ban
    log_success "Fail2ban настроен"
}

# ===========================================
# НАСТРОЙКА ПРИЛОЖЕНИЯ
# ===========================================

setup_directory() {
    log_info "Создание директории..."
    
    mkdir -p /opt/email-sender
    cd /opt/email-sender
    
    log_success "Директория создана: /opt/email-sender"
}

generate_secrets() {
    log_info "Генерация секретов..."
    
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    MARIADB_PASSWORD=$(openssl rand -hex 16)
    RABBITMQ_PASSWORD=$(openssl rand -hex 16)
    SECRET_KEY_BASE=$(openssl rand -hex 32)
    API_KEY=$(openssl rand -hex 24)
    POSTAL_SIGNING_KEY=$(openssl rand -hex 32)
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    
    log_success "Секреты сгенерированы"
}

collect_config() {
    echo ""
    echo "=========================================="
    echo "  Настройка Email Sender Infrastructure"
    echo "=========================================="
    echo ""
    
    read -p "Введите домен (например, send1.example.com): " DOMAIN
    read -p "Введите email для Let's Encrypt: " LETSENCRYPT_EMAIL
    read -p "Введите URL callback AMS (например, https://ams.example.com/webhook): " AMS_CALLBACK_URL
    read -p "Введите разрешённые домены отправителя (через запятую): " ALLOWED_SENDER_DOMAINS
    
    echo ""
}

create_env() {
    log_info "Создание .env файла..."
    
    cat > .env << EOF
# ===========================================
# AUTO-GENERATED CONFIGURATION
# Generated: $(date)
# ===========================================

DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
RAILS_ENV=production

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MARIADB_PASSWORD=${MARIADB_PASSWORD}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
API_KEY=${API_KEY}
POSTAL_SIGNING_KEY=${POSTAL_SIGNING_KEY}
WEBHOOK_SECRET=${WEBHOOK_SECRET}

AMS_CALLBACK_URL=${AMS_CALLBACK_URL}
AMS_API_KEY=
ALLOWED_SENDER_DOMAINS=${ALLOWED_SENDER_DOMAINS}
DAILY_LIMIT=50000

LOG_LEVEL=info
REDIS_URL=redis://redis:6379/0
SIDEKIQ_CONCURRENCY=10
EOF

    chmod 600 .env
    log_success ".env файл создан"
}

download_files() {
    log_info "Загрузка файлов проекта..."
    
    # TODO: Заменить на реальный URL репозитория
    # git clone https://github.com/YOUR_REPO/email-sender-infrastructure.git .
    
    log_warning "Скачайте файлы проекта вручную в /opt/email-sender"
}

# ===========================================
# ЗАПУСК
# ===========================================

start_services() {
    log_info "Запуск сервисов..."
    
    docker compose pull
    docker compose up -d postgres redis mariadb rabbitmq
    
    log_info "Ожидание инициализации баз данных (60 сек)..."
    sleep 60
    
    log_info "Инициализация Postal..."
    docker compose run --rm postal postal initialize || true
    
    docker compose up -d
    
    log_success "Сервисы запущены"
}

setup_ssl() {
    log_info "Настройка SSL сертификата..."
    
    docker compose run --rm certbot certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email ${LETSENCRYPT_EMAIL} \
        --agree-tos \
        --no-eff-email \
        -d ${DOMAIN}
    
    docker compose restart nginx
    
    log_success "SSL настроен"
}

# ===========================================
# ФИНАЛИЗАЦИЯ
# ===========================================

show_summary() {
    echo ""
    echo "=========================================="
    echo -e "  ${GREEN}Установка завершена!${NC}"
    echo "=========================================="
    echo ""
    echo "Информация о сервере:"
    echo "  Домен:     https://${DOMAIN}"
    echo "  API:       https://${DOMAIN}/api/v1/"
    echo "  Tracking:  https://${DOMAIN}/track/"
    echo ""
    echo -e "${YELLOW}ВАЖНО: Сохраните этот API ключ!${NC}"
    echo -e "${GREEN}API Key: ${API_KEY}${NC}"
    echo ""
    echo "Настройте AMS Enterprise:"
    echo "  URL:  https://${DOMAIN}/api/v1/send"
    echo "  Key:  ${API_KEY}"
    echo ""
    echo "DNS записи (настройте у регистратора):"
    echo "  ${DOMAIN}          A      YOUR_SERVER_IP"
    echo "  ${DOMAIN}          MX     10 ${DOMAIN}"
    echo "  ${DOMAIN}          TXT    \"v=spf1 ip4:YOUR_IP -all\""
    echo ""
    echo "Для получения DKIM ключа выполните:"
    echo "  docker compose exec postal postal default-dkim-record"
    echo ""
    echo "Полезные команды:"
    echo "  make status     - статус сервисов"
    echo "  make logs       - просмотр логов"
    echo "  make help       - все команды"
    echo ""
}

# ===========================================
# MAIN
# ===========================================

main() {
    echo ""
    echo "=========================================="
    echo "  Email Sender Infrastructure Installer"
    echo "=========================================="
    echo ""
    
    check_root
    check_os
    
    install_dependencies
    install_docker
    install_docker_compose
    
    setup_firewall
    setup_fail2ban
    
    setup_directory
    generate_secrets
    collect_config
    create_env
    
    download_files
    
    # Раскомментируйте после загрузки файлов:
    # start_services
    # setup_ssl
    
    show_summary
}

main "$@"

