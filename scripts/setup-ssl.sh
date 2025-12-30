#!/bin/bash

# =============================================================================
# SSL/TLS Setup Script for Email Sender Infrastructure
# Obtains Let's Encrypt certificates and configures HTTPS
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash $0"
    exit 1
fi

# Get project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Load .env
if [ ! -f .env ]; then
    print_error ".env file not found!"
    exit 1
fi

source .env

if [ -z "$DOMAIN" ]; then
    print_error "DOMAIN not set in .env file!"
    exit 1
fi

print_header "SSL/TLS SETUP FOR $DOMAIN"

# Check if certificates already exist
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_warning "Certificates already exist for $DOMAIN"
    read -p "Renew certificates? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping certificate generation"
        exit 0
    fi
fi

# Prerequisites check
print_info "Checking prerequisites..."

if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Enter admin email for Let's Encrypt: " ADMIN_EMAIL
    if [ -z "$ADMIN_EMAIL" ]; then
        print_error "Email is required!"
        exit 1
    fi
fi

print_success "Domain: $DOMAIN"
print_success "Email: $ADMIN_EMAIL"

# Verify DNS
print_info "Verifying DNS for $DOMAIN..."
SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short $DOMAIN | tail -1)

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    print_warning "DNS mismatch!"
    echo "  Server IP: $SERVER_IP"
    echo "  Domain IP: $DOMAIN_IP"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "DNS configured correctly"
fi

# Obtain certificate using certbot container
print_header "OBTAINING SSL CERTIFICATE"

print_info "Starting certbot to obtain certificate..."

docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$ADMIN_EMAIL" \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d "$DOMAIN"

if [ $? -eq 0 ]; then
    print_success "Certificate obtained successfully!"
else
    print_error "Failed to obtain certificate"
    print_info "Make sure:"
    echo "  1. Domain $DOMAIN points to this server"
    echo "  2. Port 80 is accessible from the internet"
    echo "  3. Nginx container is running"
    exit 1
fi

# Update nginx.conf with actual domain
print_header "UPDATING NGINX CONFIGURATION"

if grep -q "DOMAIN" config/nginx.conf; then
    print_info "Replacing DOMAIN placeholder with $DOMAIN..."
    sed -i "s|/etc/letsencrypt/live/DOMAIN/|/etc/letsencrypt/live/$DOMAIN/|g" config/nginx.conf
    print_success "nginx.conf updated"
else
    print_info "nginx.conf already configured"
fi

# Test nginx configuration
print_info "Testing nginx configuration..."
if docker compose exec nginx nginx -t; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration test failed!"
    exit 1
fi

# Reload nginx
print_info "Reloading nginx..."
docker compose exec nginx nginx -s reload

if [ $? -eq 0 ]; then
    print_success "Nginx reloaded successfully"
else
    print_warning "Failed to reload nginx, trying restart..."
    docker compose restart nginx
fi

# Setup auto-renewal
print_header "CONFIGURING AUTO-RENEWAL"

print_info "Certbot container will auto-renew certificates every 12 hours"
print_success "Auto-renewal configured in docker-compose.yml"

# Final check
print_header "SSL SETUP COMPLETE"

print_success "HTTPS is now enabled for $DOMAIN"
echo ""
print_info "Test your setup:"
echo "  curl https://$DOMAIN/health"
echo ""
print_info "Check certificate:"
echo "  openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null | openssl x509 -noout -dates"
echo ""
print_warning "Note: Certificates will auto-renew every 12 hours via certbot container"
