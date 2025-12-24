# ===========================================
# Local Setup Script for Email Sender (PowerShell)
# ===========================================

Write-Host "=========================================="
Write-Host "Email Sender Infrastructure - Local Setup"
Write-Host "=========================================="
Write-Host ""

# Check if .env exists
if (-not (Test-Path .env)) {
    Write-Host "Creating .env file from template..."
    Copy-Item env.example.txt .env
    Write-Host ""
    Write-Host "⚠️  IMPORTANT: Please edit .env file and set all required values!" -ForegroundColor Yellow
    Write-Host "   For local testing, you can use simple test values."
    Write-Host ""
    Read-Host "Press Enter to continue after editing .env"
}

# Check Docker
try {
    docker --version | Out-Null
    Write-Host "✅ Docker found" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker is not installed. Please install Docker first." -ForegroundColor Red
    exit 1
}

try {
    docker compose version | Out-Null
    Write-Host "✅ Docker Compose found" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker Compose is not installed. Please install Docker Compose first." -ForegroundColor Red
    exit 1
}

Write-Host ""

# Check if config files exist
if (-not (Test-Path config/nginx.conf)) {
    Write-Host "⚠️  config/nginx.conf not found. Creating from example..." -ForegroundColor Yellow
    Copy-Item config/nginx.conf.example config/nginx.conf
}

if (-not (Test-Path config/postal.yml)) {
    Write-Host "⚠️  config/postal.yml not found. Creating from example..." -ForegroundColor Yellow
    Copy-Item config/postal.yml.example config/postal.yml
}

Write-Host "Building Docker images..."
docker compose build

Write-Host ""
Write-Host "Starting services..."
docker compose up -d

Write-Host ""
Write-Host "Waiting for services to be ready..."
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "Running database migrations..."
docker compose exec api bundle exec rails db:create db:migrate

Write-Host ""
Write-Host "=========================================="
Write-Host "✅ Setup complete!" -ForegroundColor Green
Write-Host "=========================================="
Write-Host ""
Write-Host "Services are running:"
Write-Host "  - API: http://localhost:3000"
Write-Host "  - Dashboard: http://localhost/dashboard"
Write-Host "  - Health: http://localhost/health"
Write-Host "  - Sidekiq: http://localhost/sidekiq"
Write-Host ""
Write-Host "To view logs:"
Write-Host "  docker compose logs -f"
Write-Host ""
Write-Host "To stop services:"
Write-Host "  docker compose down"
Write-Host ""





