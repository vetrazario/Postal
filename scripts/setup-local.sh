#!/bin/bash
# ===========================================
# Local Setup Script for Email Sender
# ===========================================

set -e

echo "=========================================="
echo "Email Sender Infrastructure - Local Setup"
echo "=========================================="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "Creating .env file from template..."
    cp env.example.txt .env
    echo ""
    echo "⚠️  IMPORTANT: Please edit .env file and set all required values!"
    echo "   For local testing, you can use simple test values."
    echo ""
    read -p "Press Enter to continue after editing .env..."
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "✅ Docker found"
echo ""

# Check if config files exist
if [ ! -f config/nginx.conf ]; then
    echo "⚠️  config/nginx.conf not found. Using example..."
    cp config/nginx.conf.example config/nginx.conf
fi

if [ ! -f config/postal.yml ]; then
    echo "⚠️  config/postal.yml not found. Using example..."
    cp config/postal.yml.example config/postal.yml
fi

echo "Building Docker images..."
docker compose build

echo ""
echo "Starting services..."
docker compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 10

echo ""
echo "Running database migrations..."
docker compose exec api bundle exec rails db:create db:migrate

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "Services are running:"
echo "  - API: http://localhost:3000"
echo "  - Dashboard: http://localhost/dashboard"
echo "  - Health: http://localhost/health"
echo "  - Sidekiq: http://localhost/sidekiq"
echo ""
echo "To view logs:"
echo "  docker compose logs -f"
echo ""
echo "To stop services:"
echo "  docker compose down"
echo ""





