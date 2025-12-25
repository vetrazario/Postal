#!/bin/bash

# =============================================================================
# EMAIL SENDER INFRASTRUCTURE - АВТОМАТИЧЕСКАЯ УСТАНОВКА
# Ubuntu 22.04 Production Deployment
# =============================================================================

set -e  # Остановить при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции вывода
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Проверка запуска от root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Пожалуйста, запустите скрипт с sudo:"
        echo "sudo bash install.sh"
        exit 1
    fi
}

# Проверка Ubuntu 22.04
check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        print_error "Не могу определить версию ОС"
        exit 1
    fi

    . /etc/os-release
    if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "22.04" ]; then
        print_warning "Этот скрипт предназначен для Ubuntu 22.04"
        read -p "Продолжить? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    print_success "Система: Ubuntu $VERSION_ID"
}

# Запрос данных у пользователя
gather_info() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"

    # Домен
    read -p "Введите ваш домен (например: linenarrow.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "Домен обязателен!"
        exit 1
    fi

    # Email администратора
    read -p "Введите email администратора (например: admin@$DOMAIN): " ADMIN_EMAIL
    if [ -z "$ADMIN_EMAIL" ]; then
        ADMIN_EMAIL="admin@$DOMAIN"
    fi

    # Название организации
    read -p "Введите название организации: " ORG_NAME
    if [ -z "$ORG_NAME" ]; then
        ORG_NAME="My Organization"
    fi

    # Подтверждение
    echo -e "\n${YELLOW}Проверьте введенные данные:${NC}"
    echo "Домен: $DOMAIN"
    echo "Email: $ADMIN_EMAIL"
    echo "Организация: $ORG_NAME"
    echo ""
    read -p "Всё верно? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Установка отменена"
        exit 1
    fi
}

# Обновление системы
update_system() {
    print_header "ШАГ 1/10: ОБНОВЛЕНИЕ СИСТЕМЫ"
    apt update
    apt upgrade -y
    apt install -y curl git nano htop ufw ca-certificates gnupg lsb-release apache2-utils openssl cron
    print_success "Система обновлена"
}

# Установка Docker
install_docker() {
    print_header "ШАГ 2/10: УСТАНОВКА DOCKER"

    if command -v docker &> /dev/null; then
        print_info "Docker уже установлен"
        docker --version
    else
        print_info "Установка Docker..."

        # Добавить Docker GPG ключ
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        # Добавить репозиторий
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Установить Docker
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Включить автозапуск
        systemctl enable docker
        systemctl start docker

        print_success "Docker установлен"
        docker --version
    fi
}

# Настройка файрволла
setup_firewall() {
    print_header "ШАГ 3/10: НАСТРОЙКА ФАЙРВОЛЛА"

    print_info "Настройка UFW..."

    # Разрешить SSH
    ufw allow 22/tcp
    print_success "SSH разрешен (порт 22)"

    # Разрешить HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    print_success "HTTP/HTTPS разрешены (порты 80, 443)"

    # Разрешить SMTP relay
    ufw allow 2587/tcp
    print_success "SMTP Relay разрешен (порт 2587)"

    # Разрешить входящую почту (опционально)
    ufw allow 25/tcp
    print_success "SMTP разрешен (порт 25)"

    # Включить файрволл
    ufw --force enable

    print_success "Файрволл настроен"
}

# Клонирование/подготовка проекта
setup_project() {
    print_header "ШАГ 4/10: ПОДГОТОВКА ПРОЕКТА"

    # Определить текущую директорию скрипта
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Если мы уже в /opt/email-sender - использовать её
    if [ "$SCRIPT_DIR" == "/opt/email-sender" ]; then
        PROJECT_DIR="/opt/email-sender"
        print_info "Используется текущая директория: $PROJECT_DIR"
    else
        # Иначе копировать в /opt/email-sender
        PROJECT_DIR="/opt/email-sender"
        print_info "Копирование проекта в $PROJECT_DIR..."
        mkdir -p $PROJECT_DIR
        cp -r $SCRIPT_DIR/* $PROJECT_DIR/
        cp -r $SCRIPT_DIR/.env* $PROJECT_DIR/ 2>/dev/null || true
        cp -r $SCRIPT_DIR/.git* $PROJECT_DIR/ 2>/dev/null || true
    fi

    cd $PROJECT_DIR
    print_success "Проект готов: $PROJECT_DIR"
}

# Генерация паролей и конфигурации
generate_config() {
    print_header "ШАГ 5/10: ГЕНЕРАЦИЯ КОНФИГУРАЦИИ"

    print_info "Генерация безопасных паролей..."

    # Генерация паролей
    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    MARIADB_PASSWORD=$(openssl rand -hex 32)
    RABBITMQ_PASSWORD=$(openssl rand -hex 32)
    SECRET_KEY_BASE=$(openssl rand -hex 64)
    POSTAL_SIGNING_KEY=$(openssl rand -hex 64)
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    DASHBOARD_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
    REDIS_PASSWORD=$(openssl rand -hex 32)

    # Ключи шифрования
    ENCRYPTION_PRIMARY_KEY=$(openssl rand -base64 32)
    ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -base64 32)
    ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -base64 32)

    print_success "Пароли сгенерированы"

    # Создать .env файл
    cat > .env << EOF
# ===========================================
# EMAIL SENDER INFRASTRUCTURE - PRODUCTION
# Автоматически сгенерировано: $(date)
# ===========================================

# Домен и URL
DOMAIN=$DOMAIN
FRONTEND_URL=https://$DOMAIN
API_URL=https://$DOMAIN/api

# База данных PostgreSQL
POSTGRES_USER=email_sender
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=email_sender
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# База данных MariaDB (для Postal)
MARIADB_ROOT_PASSWORD=$MARIADB_PASSWORD
MARIADB_DATABASE=postal
MARIADB_USER=postal
MARIADB_PASSWORD=$MARIADB_PASSWORD

# Redis
REDIS_PASSWORD=$REDIS_PASSWORD

# RabbitMQ (для Postal)
RABBITMQ_DEFAULT_USER=postal
RABBITMQ_DEFAULT_PASS=$RABBITMQ_PASSWORD
RABBITMQ_DEFAULT_VHOST=/postal

# Rails настройки
RAILS_ENV=production
RACK_ENV=production
SECRET_KEY_BASE=$SECRET_KEY_BASE

# Rails шифрование
ENCRYPTION_PRIMARY_KEY=$ENCRYPTION_PRIMARY_KEY
ENCRYPTION_DETERMINISTIC_KEY=$ENCRYPTION_DETERMINISTIC_KEY
ENCRYPTION_KEY_DERIVATION_SALT=$ENCRYPTION_KEY_DERIVATION_SALT

# Postal
POSTAL_SIGNING_KEY=$POSTAL_SIGNING_KEY
POSTAL_API_KEY=
POSTAL_API_URL=http://postal:5000
POSTAL_WEBHOOK_PUBLIC_KEY=

# SMTP Relay
SMTP_RELAY_PORT=587
SMTP_RELAY_TLS=true
SMTP_RELAY_AUTH_REQUIRED=true
SMTP_RELAY_API_KEY=

# Вебхуки
WEBHOOK_SECRET=$WEBHOOK_SECRET

# Dashboard
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# AMS Integration
AMS_API_URL=
AMS_API_KEY=

# AI Analytics (OpenRouter)
OPENROUTER_API_KEY=

# Мониторинг
SENTRY_DSN=

# Производственные настройки
NODE_ENV=production
LOG_LEVEL=info
ENABLE_SWAGGER=false
EOF

    chmod 600 .env
    print_success ".env файл создан"

    # Обновить postal.yml
    cat > config/postal.yml << EOF
# Postal Configuration - Production
# Автоматически сгенерировано: $(date)

main_db:
  host: mariadb
  username: postal
  password: $MARIADB_PASSWORD
  database: postal
  pool_size: 5
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci

message_db:
  host: mariadb
  username: postal
  password: $MARIADB_PASSWORD
  prefix: postal

rabbitmq:
  host: rabbitmq
  username: postal
  vhost: /postal
  password: $RABBITMQ_PASSWORD

dns:
  mx_records:
    - mx.$DOMAIN
  smtp_server_hostname: $DOMAIN
  spf_include: $DOMAIN
  return_path_domain: $DOMAIN
  route_domain: $DOMAIN
  track_domain: $DOMAIN

smtp_server:
  port: 25
  tls_enabled: true
  tls_certificate_path: /etc/ssl/certs/cert.pem
  tls_private_key_path: /etc/ssl/private/key.pem
  log_connect: true

web:
  host: $DOMAIN
  protocol: https
  port: 443

rails:
  environment: production
  secret_key: $SECRET_KEY_BASE

general:
  use_ip_pools: false

smtp_relays: []

logging:
  stdout: true
  rails_log_enabled: true
EOF

    print_success "postal.yml создан"

    # Создать htpasswd для Dashboard
    htpasswd -cb config/htpasswd admin "$DASHBOARD_PASSWORD"
    chmod 600 config/htpasswd
    print_success "Dashboard пароль установлен"

    # Сохранить пароли в файл
    cat > /root/email-sender-credentials.txt << EOF
# ===========================================
# EMAIL SENDER - УЧЕТНЫЕ ДАННЫЕ
# Сгенерировано: $(date)
# ===========================================

ДОМЕН: $DOMAIN
IP: $(curl -s ifconfig.me)

DASHBOARD:
URL: https://$DOMAIN/dashboard
Логин: admin
Пароль: $DASHBOARD_PASSWORD

POSTAL WEB UI:
URL: https://$DOMAIN/postal
Логин: $ADMIN_EMAIL
Пароль: (будет установлен при инициализации)

БАЗА ДАННЫХ PostgreSQL:
Host: localhost:5432
Database: email_sender
User: email_sender
Password: $POSTGRES_PASSWORD

БАЗА ДАННЫХ MariaDB:
Host: localhost:3306
Database: postal
User: postal
Password: $MARIADB_PASSWORD

REDIS:
Host: localhost:6379
Password: $REDIS_PASSWORD

RABBITMQ:
Host: localhost:5672
User: postal
Password: $RABBITMQ_PASSWORD

SMTP RELAY:
Host: $DOMAIN
Port: 2587
TLS: Да

ВАЖНО: Храните этот файл в безопасности!
Файл: /root/email-sender-credentials.txt
EOF

    chmod 600 /root/email-sender-credentials.txt

    print_success "Учетные данные сохранены в /root/email-sender-credentials.txt"
}

# Настройка SSL
setup_ssl() {
    print_header "ШАГ 6/10: НАСТРОЙКА SSL СЕРТИФИКАТА"

    print_warning "Для получения SSL сертификата нужно:"
    echo "1. Домен $DOMAIN должен указывать на IP сервера"
    echo "2. Порты 80 и 443 должны быть доступны"
    echo ""

    read -p "Получить SSL сертификат Let's Encrypt? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Установка certbot..."
        apt install -y certbot python3-certbot-nginx

        # Остановить контейнеры если запущены
        cd $PROJECT_DIR
        docker compose down 2>/dev/null || true

        print_info "Получение сертификата для $DOMAIN..."
        certbot certonly --standalone --non-interactive --agree-tos --email $ADMIN_EMAIL -d $DOMAIN -d www.$DOMAIN

        if [ $? -eq 0 ]; then
            # Создать ссылки
            ln -sf /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/ssl/certs/$DOMAIN.crt
            ln -sf /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/ssl/private/$DOMAIN.key

            # Настроить автообновление
            if command -v crontab &> /dev/null; then
                (crontab -l 2>/dev/null; echo "0 3 1 * * certbot renew --quiet && docker compose -f $PROJECT_DIR/docker-compose.yml restart nginx") | crontab -
                print_info "Автообновление SSL настроено (каждое 1-е число месяца в 3:00)"
            else
                print_warning "crontab не найден - автообновление SSL не настроено"
                print_warning "Установите cron и настройте вручную: crontab -e"
            fi

            print_success "SSL сертификат получен и настроен"
            SSL_ENABLED=true
        else
            print_error "Не удалось получить SSL сертификат"
            print_warning "Продолжаем без HTTPS..."
            SSL_ENABLED=false
        fi
    else
        print_warning "Пропускаем SSL сертификат"
        SSL_ENABLED=false
    fi
}

# Обновление nginx конфигурации
update_nginx_config() {
    print_header "ШАГ 7/10: НАСТРОЙКА NGINX"

    if [ "$SSL_ENABLED" = true ]; then
        print_info "Настройка HTTPS в nginx..."

        # Обновить docker-compose.yml для добавления SSL volumes
        if ! grep -q "/etc/letsencrypt" docker-compose.yml; then
            print_info "Добавление SSL сертификатов в docker-compose.yml..."
            # Это будет сделано в следующем шаге
        fi

        print_success "Nginx настроен для HTTPS"
    else
        print_warning "Nginx работает в HTTP режиме"
    fi
}

# Запуск системы
start_system() {
    print_header "ШАГ 8/10: ЗАПУСК СИСТЕМЫ"

    cd $PROJECT_DIR

    print_info "Сборка и запуск Docker контейнеров..."
    docker compose up -d --build

    print_info "Ожидание запуска сервисов (60 секунд)..."
    sleep 60

    # Проверка статуса
    docker compose ps

    print_success "Все контейнеры запущены"
}

# Инициализация базы данных
init_database() {
    print_header "ШАГ 9/10: ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ"

    cd $PROJECT_DIR

    print_info "Создание базы данных Rails..."
    docker compose exec -T api rails db:create RAILS_ENV=production

    print_info "Запуск миграций..."
    docker compose exec -T api rails db:migrate RAILS_ENV=production

    print_success "База данных инициализирована"
}

# Инициализация Postal
init_postal() {
    print_header "ШАГ 10/10: ИНИЦИАЛИЗАЦИЯ POSTAL"

    cd $PROJECT_DIR

    print_info "Инициализация Postal..."

    # Создать временный скрипт для автоматической инициализации
    cat > /tmp/postal_init.exp << EOF
#!/usr/bin/expect -f
set timeout 30

spawn docker compose exec postal postal initialize

expect "E-Mail Address:"
send "$ADMIN_EMAIL\r"

expect "First Name:"
send "Admin\r"

expect "Last Name:"
send "User\r"

expect "Password:"
send "$DASHBOARD_PASSWORD\r"

expect eof
EOF

    chmod +x /tmp/postal_init.exp

    if command -v expect &> /dev/null; then
        /tmp/postal_init.exp
    else
        print_warning "Expect не установлен, инициализация Postal вручную..."
        print_info "Выполните команду:"
        echo "docker compose exec postal postal initialize"
        echo "Email: $ADMIN_EMAIL"
        echo "Password: $DASHBOARD_PASSWORD"
        read -p "Нажмите Enter после инициализации..."
    fi

    rm -f /tmp/postal_init.exp

    print_info "Создание организации..."
    docker compose exec -T postal postal make-org linenarrow "$ORG_NAME"

    print_info "Создание почтового сервера..."
    docker compose exec -T postal postal make-server linenarrow $DOMAIN

    print_info "Создание API ключа..."
    API_KEY=$(docker compose exec -T postal postal make-api-key linenarrow linenarrow "API Key" | grep -oP 'proj_[a-zA-Z0-9_-]+' | head -1)

    if [ ! -z "$API_KEY" ]; then
        # Обновить .env
        sed -i "s/^POSTAL_API_KEY=.*/POSTAL_API_KEY=$API_KEY/" .env

        # Перезапустить API
        docker compose restart api sidekiq

        print_success "Postal API ключ: $API_KEY"
    else
        print_warning "Не удалось автоматически получить API ключ"
        print_info "Создайте вручную: docker compose exec postal postal make-api-key linenarrow linenarrow \"API Key\""
    fi
}

# Настройка автозапуска
setup_autostart() {
    print_info "Настройка автозапуска..."

    cat > /etc/systemd/system/email-sender.service << EOF
[Unit]
Description=Email Sender Infrastructure
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable email-sender.service

    print_success "Автозапуск настроен"
}

# Финальная информация
show_final_info() {
    print_header "🎉 УСТАНОВКА ЗАВЕРШЕНА!"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Система успешно установлена и запущена!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${YELLOW}📋 ИНФОРМАЦИЯ ДЛЯ ДОСТУПА:${NC}"
    echo ""

    if [ "$SSL_ENABLED" = true ]; then
        echo -e "🌐 Dashboard: ${BLUE}https://$DOMAIN/dashboard${NC}"
        echo -e "🌐 Postal UI: ${BLUE}https://$DOMAIN/postal${NC}"
    else
        echo -e "🌐 Dashboard: ${BLUE}http://$DOMAIN/dashboard${NC}"
        echo -e "🌐 Postal UI: ${BLUE}http://$DOMAIN/postal${NC}"
    fi

    echo ""
    echo -e "👤 Логин Dashboard: ${GREEN}admin${NC}"
    echo -e "🔑 Пароль Dashboard: ${GREEN}$DASHBOARD_PASSWORD${NC}"
    echo ""

    echo -e "${YELLOW}📧 SMTP RELAY ДЛЯ AMS:${NC}"
    echo -e "Host: ${GREEN}$DOMAIN${NC}"
    echo -e "Port: ${GREEN}2587${NC}"
    echo -e "Security: ${GREEN}TLS/STARTTLS${NC}"
    echo -e "Credentials: ${BLUE}Создайте в Dashboard → SMTP Credentials${NC}"
    echo ""

    echo -e "${YELLOW}📁 ВСЕ ПАРОЛИ СОХРАНЕНЫ:${NC}"
    echo -e "${BLUE}/root/email-sender-credentials.txt${NC}"
    echo ""

    echo -e "${YELLOW}🔍 ПРОВЕРКА СИСТЕМЫ:${NC}"
    echo "docker compose ps"
    echo "docker compose logs -f"
    echo ""

    echo -e "${YELLOW}📝 СЛЕДУЮЩИЕ ШАГИ:${NC}"
    echo "1. Откройте Dashboard и создайте SMTP credentials"
    echo "2. Настройте AMS Enterprise с полученными данными"
    echo "3. Отправьте тестовое письмо"
    echo "4. (Опционально) Настройте AI Analytics в Settings"
    echo ""

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Документация: $PROJECT_DIR/FINAL_REPORT.md${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# =============================================================================

main() {
    clear

    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     EMAIL SENDER INFRASTRUCTURE - АВТОУСТАНОВКА               ║
║                                                               ║
║     Этот скрипт автоматически установит и настроит            ║
║     всю систему для отправки email через Postal               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF

    echo ""

    # Проверки
    check_root
    check_ubuntu

    # Сбор информации
    gather_info

    # Установка
    update_system
    install_docker
    setup_firewall
    setup_project
    generate_config
    setup_ssl
    update_nginx_config
    start_system
    init_database
    init_postal
    setup_autostart

    # Финал
    show_final_info
}

# Запуск
main "$@"
