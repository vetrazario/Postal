#!/bin/bash
# ===========================================
# CHECK POSTAL STATUS
# Comprehensive diagnostics for Postal
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}[✓]${NC} $1"
}

check_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

echo ""
echo "=========================================="
echo "  Postal Status Check"
echo "=========================================="
echo ""

# 1. Check if Docker is running
check_info "Checking Docker..."
if ! docker info &> /dev/null; then
    check_fail "Docker is not running!"
    exit 1
fi
check_pass "Docker is running"

# 2. Check if containers are running
echo ""
check_info "Checking containers..."

CONTAINERS=("email_postgres" "email_redis" "email_mariadb" "email_rabbitmq" "email_postal" "email_nginx")

for container in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null || echo "no healthcheck")
        if [ "$STATUS" == "healthy" ]; then
            check_pass "$container: running (healthy)"
        elif [ "$STATUS" == "no healthcheck" ]; then
            check_pass "$container: running (no healthcheck)"
        else
            check_warn "$container: running (status: $STATUS)"
        fi
    else
        check_fail "$container: not running"
    fi
done

# 3. Check postal.yml configuration
echo ""
check_info "Checking postal.yml configuration..."

if [ ! -f config/postal.yml ]; then
    check_fail "config/postal.yml not found!"
    echo "  Run: sudo bash scripts/fix-postal-config.sh"
else
    # Check for unsubstituted variables
    UNSUBST=$(grep -c '\${' config/postal.yml 2>/dev/null || echo "0")
    if [ "$UNSUBST" -gt 0 ]; then
        check_fail "Found unsubstituted variables in postal.yml"
        echo "  Variables found:"
        grep '\${' config/postal.yml | sed 's/^/    /'
        echo "  Run: sudo bash scripts/fix-postal-config.sh"
    else
        check_pass "postal.yml: all variables substituted"
    fi

    # Check domain
    DOMAIN=$(grep -A 1 "^web:" config/postal.yml | grep "host:" | awk '{print $2}')
    check_info "Configured domain: $DOMAIN"
fi

# 4. Check database connection
echo ""
check_info "Checking database connections..."

# Load .env if exists
if [ -f .env ]; then
    source .env

    # Check MariaDB
    if docker exec email_mariadb mysql -upostal -p${MARIADB_PASSWORD} -e "SELECT 1" &> /dev/null; then
        check_pass "MariaDB: connection successful"
    else
        check_fail "MariaDB: connection failed"
        echo "  Check MARIADB_PASSWORD in .env and postal.yml"
    fi

    # Check if Postal database exists
    DB_EXISTS=$(docker exec email_mariadb mysql -upostal -p${MARIADB_PASSWORD} -e "SHOW DATABASES LIKE 'postal';" 2>/dev/null | grep -c postal || echo "0")
    if [ "$DB_EXISTS" -gt 0 ]; then
        check_pass "MariaDB: postal database exists"

        # Check if tables exist
        TABLE_COUNT=$(docker exec email_mariadb mysql -upostal -p${MARIADB_PASSWORD} postal -e "SHOW TABLES;" 2>/dev/null | wc -l)
        if [ "$TABLE_COUNT" -gt 10 ]; then
            check_pass "MariaDB: $TABLE_COUNT tables found (initialized)"
        else
            check_warn "MariaDB: only $TABLE_COUNT tables found (may need initialization)"
            echo "  Run: docker compose exec postal postal initialize"
        fi
    else
        check_fail "MariaDB: postal database not found"
        echo "  Run: docker compose exec postal postal initialize"
    fi
else
    check_warn ".env file not found, skipping database check"
fi

# 5. Check if Postal web server is responding
echo ""
check_info "Checking Postal web interface..."

# Direct port 5000
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 2>/dev/null | grep -q "200\|302\|401"; then
    check_pass "Postal web server: responding on port 5000"
else
    check_fail "Postal web server: not responding on port 5000"
    echo "  Check logs: docker compose logs postal --tail=50"
fi

# Through nginx on /postal/
if curl -s -o /dev/null -w "%{http_code}" http://localhost/postal/ 2>/dev/null | grep -q "200\|302\|401"; then
    check_pass "Nginx proxy: /postal/ route working"
else
    check_warn "Nginx proxy: /postal/ route not working"
    echo "  Check if nginx.conf has location /postal/ block"
    echo "  Restart nginx: docker compose restart nginx"
fi

# 6. Check nginx configuration
echo ""
check_info "Checking nginx configuration..."

if grep -q "location /postal/" config/nginx.conf; then
    check_pass "nginx.conf: /postal/ route configured"
else
    check_fail "nginx.conf: /postal/ route NOT configured"
    echo "  Add this to nginx.conf after 'location /track/'"
    echo ""
    echo "  location /postal/ {"
    echo "      proxy_pass http://postal_backend/;"
    echo "      proxy_http_version 1.1;"
    echo "      proxy_set_header Host \$host;"
    echo "      proxy_set_header X-Real-IP \$remote_addr;"
    echo "      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "      proxy_set_header X-Forwarded-Proto \$scheme;"
    echo "  }"
    echo ""
fi

# 7. Check for Postal users
echo ""
check_info "Checking Postal users..."

if [ -f .env ]; then
    source .env
    USER_COUNT=$(docker exec email_mariadb mysql -upostal -p${MARIADB_PASSWORD} postal -e "SELECT COUNT(*) FROM users;" 2>/dev/null | tail -1)

    if [ -n "$USER_COUNT" ] && [ "$USER_COUNT" -gt 0 ]; then
        check_pass "Postal: $USER_COUNT user(s) found"
    else
        check_warn "Postal: no users found"
        echo "  Create admin user: docker compose exec postal postal make-user"
    fi
fi

# 8. Summary
echo ""
echo "=========================================="
echo "  Diagnostic Summary"
echo "=========================================="
echo ""

# Count issues
ISSUES=0

docker ps --format '{{.Names}}' | grep -q "^email_postal$" || ((ISSUES++))
[ -f config/postal.yml ] || ((ISSUES++))
grep -q '\${' config/postal.yml 2>/dev/null && ((ISSUES++))
curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 2>/dev/null | grep -q "200\|302\|401" || ((ISSUES++))

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Postal web interface should be available at:"
    echo "  - http://localhost:5000"
    echo "  - http://localhost/postal/"
    echo ""
else
    echo -e "${RED}✗ Found $ISSUES issue(s)${NC}"
    echo ""
    echo "To fix common issues:"
    echo "1. Fix postal.yml: sudo bash scripts/fix-postal-config.sh"
    echo "2. Restart services: docker compose restart postal nginx"
    echo "3. Initialize database: docker compose exec postal postal initialize"
    echo "4. Create user: docker compose exec postal postal make-user"
    echo ""
    echo "For detailed diagnostics, see POSTAL_WEB_FIX.md"
    echo ""
fi
