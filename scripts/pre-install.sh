#!/bin/bash
# ===========================================
# PRE-INSTALLATION SCRIPT
# Prepares all required files before installation
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
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "  Pre-Installation Setup"
echo "=========================================="
echo ""

# 1. Check and create .env file
log_info "Checking .env file..."
if [ ! -f .env ]; then
    log_warning ".env file not found, creating from template..."
    cp env.example.txt .env

    # Generate random secrets
    log_info "Generating secure random secrets..."
    POSTGRES_PWD=$(openssl rand -hex 16)
    MARIADB_PWD=$(openssl rand -hex 16)
    RABBITMQ_PWD=$(openssl rand -hex 16)
    SECRET_KEY=$(openssl rand -hex 32)
    API_KEY_VAL=$(openssl rand -hex 24)
    POSTAL_KEY=$(openssl rand -hex 32)
    WEBHOOK_SEC=$(openssl rand -hex 32)

    # Generate Dashboard credentials
    DASHBOARD_PWD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

    # Replace CHANGE_ME values with generated secrets
    sed -i "s/POSTGRES_PASSWORD=CHANGE_ME_GENERATE_RANDOM/POSTGRES_PASSWORD=$POSTGRES_PWD/" .env
    sed -i "s/MARIADB_PASSWORD=CHANGE_ME_GENERATE_RANDOM/MARIADB_PASSWORD=$MARIADB_PWD/" .env
    sed -i "s/RABBITMQ_PASSWORD=CHANGE_ME_GENERATE_RANDOM/RABBITMQ_PASSWORD=$RABBITMQ_PWD/" .env
    sed -i "s/SECRET_KEY_BASE=CHANGE_ME_GENERATE_64_HEX/SECRET_KEY_BASE=$SECRET_KEY/" .env
    sed -i "s/API_KEY=CHANGE_ME_GENERATE_48_HEX/API_KEY=$API_KEY_VAL/" .env
    sed -i "s/POSTAL_SIGNING_KEY=CHANGE_ME_GENERATE_64_HEX/POSTAL_SIGNING_KEY=$POSTAL_KEY/" .env
    sed -i "s/WEBHOOK_SECRET=CHANGE_ME_GENERATE_64_HEX/WEBHOOK_SECRET=$WEBHOOK_SEC/" .env
    sed -i "s/DASHBOARD_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD/DASHBOARD_PASSWORD=$DASHBOARD_PWD/" .env

    log_success ".env file created with generated secrets"
    log_warning "IMPORTANT: Edit .env and set DOMAIN, LETSENCRYPT_EMAIL, and other required values!"
    echo ""
    log_info "Dashboard credentials (save these!):"
    echo "  Username: admin"
    echo "  Password: $DASHBOARD_PWD"
    echo ""
else
    log_success ".env file already exists"
fi

# 2. Install envsubst if not available (required for postal.yml generation)
log_info "Checking for envsubst utility..."
if ! command -v envsubst &> /dev/null; then
    log_warning "envsubst not found, installing gettext-base..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y gettext-base
        log_success "envsubst installed"
    else
        log_error "Cannot install envsubst automatically. Please install gettext-base package manually."
        exit 1
    fi
else
    log_success "envsubst is available"
fi

# 3. Generate postal.yml from template
log_info "Generating config/postal.yml from template..."
if [ -f .env ]; then
    # Load environment variables
    set -a
    source .env
    set +a

    # Generate postal.yml
    envsubst < config/postal.yml.example > config/postal.yml
    log_success "config/postal.yml generated"
else
    log_error ".env file not found, cannot generate postal.yml"
    exit 1
fi

# 4. Create htpasswd file if missing
log_info "Checking config/htpasswd..."
if [ ! -f config/htpasswd ]; then
    log_warning "config/htpasswd not found, creating default..."

    # Try to use htpasswd if available, otherwise use openssl
    if command -v htpasswd &> /dev/null; then
        htpasswd -b -c config/htpasswd admin admin123
    else
        # Use openssl as fallback
        HASH=$(openssl passwd -apr1 "admin123")
        echo "admin:$HASH" > config/htpasswd
    fi

    chmod 600 config/htpasswd
    log_success "config/htpasswd created (user: admin, password: admin123)"
    log_warning "IMPORTANT: Change the default password in production!"
else
    log_success "config/htpasswd already exists"
fi

# 5. Create necessary directories
log_info "Creating necessary directories..."
mkdir -p config tmp log
log_success "Directories created"

# 6. Check Docker
log_info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed!"
    log_info "Install Docker with: curl -fsSL https://get.docker.com | sh"
    exit 1
fi
log_success "Docker is installed"

# 7. Check Docker Compose
log_info "Checking Docker Compose..."
if ! docker compose version &> /dev/null 2>&1; then
    log_error "Docker Compose is not installed!"
    log_info "Install with: sudo apt-get install docker-compose-plugin"
    exit 1
fi
log_success "Docker Compose is installed"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Pre-installation complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit .env and configure DOMAIN, LETSENCRYPT_EMAIL, etc."
echo "2. Run: docker compose up -d"
echo "3. Initialize database: docker compose exec api rails db:create db:migrate"
echo ""
log_warning "Remember to change default htpasswd credentials!"
echo ""
