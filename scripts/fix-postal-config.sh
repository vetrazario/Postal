#!/bin/bash
# ===========================================
# FIX POSTAL CONFIGURATION
# Fixes postal.yml variable substitution
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo ""
echo "=========================================="
echo "  Postal Configuration Fix"
echo "=========================================="
echo ""

# 1. Check if .env exists
if [ ! -f .env ]; then
    log_error ".env file not found!"
    log_info "Please run: sudo bash scripts/pre-install.sh"
    exit 1
fi

log_success ".env file found"

# 2. Load environment variables
log_info "Loading environment variables..."
set -a
source .env
set +a

# 3. Check if required variables are set
log_info "Checking required variables..."

REQUIRED_VARS=(
    "MARIADB_PASSWORD"
    "RABBITMQ_PASSWORD"
    "SECRET_KEY_BASE"
    "DOMAIN"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    log_error "Missing required variables in .env:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    log_info "Please edit .env and set these variables"
    exit 1
fi

log_success "All required variables are set"

# 4. Check if envsubst is installed
if ! command -v envsubst &> /dev/null; then
    log_warning "envsubst not found, installing..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y gettext-base
        log_success "envsubst installed"
    else
        log_error "Cannot install envsubst. Please install gettext-base manually"
        exit 1
    fi
else
    log_success "envsubst is available"
fi

# 5. Backup existing postal.yml if it exists and is different from example
if [ -f config/postal.yml ]; then
    log_info "Backing up existing postal.yml..."
    cp config/postal.yml config/postal.yml.backup.$(date +%Y%m%d_%H%M%S)
    log_success "Backup created"
fi

# 6. Generate postal.yml from template
log_info "Generating config/postal.yml from template..."

if [ ! -f config/postal.yml.example ]; then
    log_error "Template file config/postal.yml.example not found!"
    exit 1
fi

envsubst < config/postal.yml.example > config/postal.yml

log_success "config/postal.yml generated"

# 7. Verify that variables were substituted
log_info "Verifying variable substitution..."

UNSUBSTITUTED=$(grep -c '\${' config/postal.yml || true)

if [ "$UNSUBSTITUTED" -gt 0 ]; then
    log_error "Found $UNSUBSTITUTED unsubstituted variables in postal.yml:"
    grep '\${' config/postal.yml | sed 's/^/  /'
    log_warning "Some variables may be missing from .env"
    exit 1
fi

log_success "All variables substituted successfully"

# 8. Validate critical values
log_info "Validating configuration..."

# Check MariaDB password
MARIADB_PASS_IN_CONFIG=$(grep -A 1 "main_db:" config/postal.yml | grep "password:" | awk '{print $2}')
if [ -z "$MARIADB_PASS_IN_CONFIG" ] || [ "$MARIADB_PASS_IN_CONFIG" == "\${MARIADB_PASSWORD}" ]; then
    log_error "MariaDB password not substituted in postal.yml!"
    exit 1
fi

# Check domain
DOMAIN_IN_CONFIG=$(grep -A 1 "^web:" config/postal.yml | grep "host:" | awk '{print $2}')
if [ -z "$DOMAIN_IN_CONFIG" ] || [ "$DOMAIN_IN_CONFIG" == "\${DOMAIN}" ]; then
    log_error "Domain not substituted in postal.yml!"
    exit 1
fi

log_success "Configuration validated"

# 9. Show summary
echo ""
echo "=========================================="
echo -e "${GREEN}✓ Configuration Fixed!${NC}"
echo "=========================================="
echo ""
echo "Configuration summary:"
echo "  Domain:          $DOMAIN_IN_CONFIG"
echo "  MariaDB Host:    mariadb"
echo "  RabbitMQ Host:   rabbitmq"
echo ""
echo "Next steps:"
echo "1. Restart Postal:"
echo "   docker compose restart postal"
echo ""
echo "2. Wait for startup (30 seconds):"
echo "   sleep 30"
echo ""
echo "3. Initialize Postal (if not done):"
echo "   docker compose exec postal postal initialize"
echo ""
echo "4. Create admin user (if not done):"
echo "   docker compose exec postal postal make-user"
echo ""
echo "5. Restart nginx with new config:"
echo "   docker compose restart nginx"
echo ""
echo "6. Access Postal web interface:"
echo "   http://your-server-ip:5000"
echo "   http://your-server-ip/postal/"
echo ""
