#!/bin/bash
# ===========================================
# EMAIL SENDER INFRASTRUCTURE
# Create .htpasswd file for Basic Auth
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

# Путь к файлу
HTPASSWD_FILE="config/htpasswd"

# Проверка наличия утилит
check_dependencies() {
    if command -v htpasswd &> /dev/null; then
        USE_HTPASSWD=true
    elif command -v openssl &> /dev/null; then
        USE_HTPASSWD=false
        log_warning "htpasswd не найден, будет использован openssl"
    else
        log_error "Не найдены ни htpasswd, ни openssl. Установите один из них:"
        echo "  apt-get install apache2-utils  # для htpasswd"
        echo "  apt-get install openssl        # для openssl"
        exit 1
    fi
}

# Генерация пароля
generate_password() {
    openssl rand -base64 24 | tr -d "=+/" | cut -c1-16
}

# Создание файла с htpasswd
create_with_htpasswd() {
    local username=$1
    local password=$2
    
    if [ -f "$HTPASSWD_FILE" ]; then
        log_warning "Файл $HTPASSWD_FILE уже существует. Добавляю пользователя..."
        htpasswd -b "$HTPASSWD_FILE" "$username" "$password"
    else
        log_info "Создание нового файла $HTPASSWD_FILE..."
        htpasswd -b -c "$HTPASSWD_FILE" "$username" "$password"
    fi
    
    chmod 600 "$HTPASSWD_FILE"
}

# Создание файла с openssl
create_with_openssl() {
    local username=$1
    local password=$2
    
    # Генерируем хеш пароля
    local hash=$(openssl passwd -apr1 "$password")
    
    if [ -f "$HTPASSWD_FILE" ]; then
        log_warning "Файл $HTPASSWD_FILE уже существует. Добавляю пользователя..."
        echo "$username:$hash" >> "$HTPASSWD_FILE"
    else
        log_info "Создание нового файла $HTPASSWD_FILE..."
        echo "$username:$hash" > "$HTPASSWD_FILE"
    fi
    
    chmod 600 "$HTPASSWD_FILE"
}

# Загрузка переменных окружения
load_env() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(dirname "$script_dir")"

    if [ -f "$project_dir/.env" ]; then
        log_info "Загрузка переменных из .env..."
        set -a
        source "$project_dir/.env"
        set +a
    fi
}

# Основная функция
main() {
    echo ""
    echo "=========================================="
    echo "  Создание .htpasswd файла"
    echo "=========================================="
    echo ""

    check_dependencies
    load_env

    # Получение параметров (приоритет: аргументы > переменные окружения > интерактивный ввод)
    local username="${1:-${DASHBOARD_USERNAME:-}}"
    local password="${2:-${DASHBOARD_PASSWORD:-}}"

    if [ -z "$username" ]; then
        read -p "Введите имя пользователя [admin]: " username
        username=${username:-admin}
    fi

    if [ -z "$password" ]; then
        read -sp "Введите пароль (или нажмите Enter для автогенерации): " password
        echo ""

        if [ -z "$password" ]; then
            password=$(generate_password)
            log_info "Сгенерирован пароль: $password"
            log_warning "Сохраните этот пароль! Он больше не будет показан."
        fi
    else
        log_info "Используется пароль из переменной окружения"
    fi
    
    # Создание директории если нужно
    mkdir -p "$(dirname "$HTPASSWD_FILE")"
    
    # Создание файла
    if [ "$USE_HTPASSWD" = true ]; then
        create_with_htpasswd "$username" "$password"
    else
        create_with_openssl "$username" "$password"
    fi
    
    log_success "Файл $HTPASSWD_FILE создан успешно"
    echo ""
    echo "Использование:"
    echo "  Username: $username"
    if [ -n "${2:-}" ] || [ -z "${2:-}" ] && [ -n "$password" ]; then
        echo "  Password: $password"
    fi
    echo ""
}

main "$@"

