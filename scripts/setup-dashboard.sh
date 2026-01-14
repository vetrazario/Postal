#!/bin/bash
# ===========================================
# SETUP DASHBOARD CREDENTIALS
# Configures Dashboard authentication
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
echo "  Dashboard Credentials Setup"
echo "=========================================="
echo ""

# 1. Check if .env exists
if [ ! -f .env ]; then
    log_error ".env file not found!"
    log_info "Please run: sudo bash scripts/pre-install.sh"
    exit 1
fi

log_success ".env file found"

# 2. Check current credentials
CURRENT_USERNAME=$(grep "^DASHBOARD_USERNAME=" .env 2>/dev/null | cut -d= -f2)
CURRENT_PASSWORD=$(grep "^DASHBOARD_PASSWORD=" .env 2>/dev/null | cut -d= -f2)

if [ -n "$CURRENT_USERNAME" ] && [ -n "$CURRENT_PASSWORD" ]; then
    # Check if password is still the default placeholder
    if [ "$CURRENT_PASSWORD" == "CHANGE_ME_GENERATE_STRONG_PASSWORD" ]; then
        log_warning "Dashboard password is still the default placeholder!"
        NEED_NEW_PASSWORD=true
    else
        log_info "Dashboard credentials already configured:"
        echo "   Username: $CURRENT_USERNAME"
        echo "   Password: $CURRENT_PASSWORD"
        echo ""
        read -p "Do you want to generate new credentials? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_success "Keeping existing credentials"
            exit 0
        fi
        NEED_NEW_PASSWORD=true
    fi
else
    log_warning "Dashboard credentials not found in .env"
    NEED_NEW_PASSWORD=true
fi

# 3. Generate new credentials
if [ "$NEED_NEW_PASSWORD" = true ]; then
    log_info "Generating new Dashboard credentials..."

    # Username (default: admin)
    read -p "Enter username [admin]: " USERNAME
    USERNAME=${USERNAME:-admin}

    # Password (auto-generate)
    read -p "Generate random password? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
        log_success "Generated random password"
    else
        read -sp "Enter password: " PASSWORD
        echo ""
        if [ -z "$PASSWORD" ]; then
            log_error "Password cannot be empty!"
            exit 1
        fi
    fi

    # 4. Update .env file
    log_info "Updating .env file..."

    # Remove old entries if they exist
    sed -i '/^DASHBOARD_USERNAME=/d' .env
    sed -i '/^DASHBOARD_PASSWORD=/d' .env

    # Add new entries
    echo "DASHBOARD_USERNAME=$USERNAME" >> .env
    echo "DASHBOARD_PASSWORD=$PASSWORD" >> .env

    log_success "Dashboard credentials updated in .env"
fi

# 5. Show credentials
echo ""
echo "=========================================="
echo -e "${GREEN}✓ Dashboard Credentials${NC}"
echo "=========================================="
echo ""
echo "  Username: $USERNAME"
echo "  Password: $PASSWORD"
echo ""
echo -e "${YELLOW}⚠️  SAVE THESE CREDENTIALS!${NC}"
echo ""

# 6. Restart services
read -p "Restart API and Sidekiq to apply changes? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Restarting services..."

    if command -v docker &> /dev/null; then
        docker compose restart api sidekiq 2>/dev/null || log_warning "Could not restart services (Docker not available)"
        log_success "Services restarted"
    else
        log_warning "Docker not found, please restart services manually:"
        echo "   docker compose restart api sidekiq"
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Access Dashboard at:"
echo "  http://your-server-ip/dashboard"
echo ""
echo "Login with:"
echo "  Username: $USERNAME"
echo "  Password: $PASSWORD"
echo ""
