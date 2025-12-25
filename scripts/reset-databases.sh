#!/bin/bash
# ===========================================
# RESET DATABASES
# Use this when passwords in .env don't match existing databases
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
echo "  Database Reset Script"
echo "=========================================="
echo ""

log_warning "This will DELETE all data in PostgreSQL and MariaDB!"
log_warning "Press Ctrl+C to cancel, or Enter to continue..."
read

# Stop all containers
log_info "Stopping all containers..."
docker compose down
log_success "Containers stopped"

# Remove database volumes
log_info "Removing database volumes..."
docker volume rm email_postgres_data 2>/dev/null || log_warning "PostgreSQL volume not found (might be already deleted)"
docker volume rm email_mariadb_data 2>/dev/null || log_warning "MariaDB volume not found (might be already deleted)"
log_success "Database volumes removed"

# Start databases first
log_info "Starting databases (PostgreSQL, MariaDB, Redis, RabbitMQ)..."
docker compose up -d postgres mariadb redis rabbitmq

# Wait for databases to initialize
log_info "Waiting for databases to initialize (60 seconds)..."
for i in {60..1}; do
    printf "\rTime remaining: %02d seconds" $i
    sleep 1
done
echo ""

# Check database health
log_info "Checking database health..."
docker compose ps postgres mariadb redis rabbitmq

# Start remaining services
log_info "Starting remaining services..."
docker compose up -d

log_success "All services started!"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Database reset complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Wait for all services to become healthy (check with: docker compose ps)"
echo "2. Initialize Postal database: docker compose exec postal postal initialize"
echo "3. Create Postal user: docker compose exec postal postal make-user"
echo ""
