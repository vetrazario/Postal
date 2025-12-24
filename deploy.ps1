# Email Sender Infrastructure Deployment Script

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Email Sender Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker
Write-Host "Step 1: Checking Docker..." -ForegroundColor Yellow
try {
    docker --version | Out-Null
    docker compose version | Out-Null
    docker info | Out-Null
    Write-Host "  OK: Docker is ready" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Docker is not installed or not running!" -ForegroundColor Red
    Write-Host "  Install Docker Desktop and start it" -ForegroundColor Yellow
    exit 1
}

# Check .env
Write-Host "Step 2: Checking configuration..." -ForegroundColor Yellow
if (-not (Test-Path .env)) {
    Write-Host "  WARNING: .env not found, creating from template..." -ForegroundColor Yellow
    Copy-Item env.example.txt .env
    Write-Host "  WARNING: Edit .env file before continuing!" -ForegroundColor Yellow
    Read-Host "Press Enter after editing .env"
}

# Check configs
if (-not (Test-Path config/nginx.conf)) {
    Write-Host "  WARNING: config/nginx.conf not found" -ForegroundColor Yellow
}

if (-not (Test-Path config/postal.yml)) {
    Write-Host "  WARNING: config/postal.yml not found" -ForegroundColor Yellow
}

Write-Host "  OK: Configuration ready" -ForegroundColor Green

# Stop old containers
Write-Host "Step 3: Stopping old containers..." -ForegroundColor Yellow
docker compose down 2>&1 | Where-Object { $_ -notmatch "warning" -and $_ -notmatch "obsolete" } | Out-Null
Write-Host "  OK: Done" -ForegroundColor Green

# Build images
Write-Host "Step 4: Building Docker images..." -ForegroundColor Yellow
Write-Host "  This may take several minutes..." -ForegroundColor Gray
docker compose build
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Images built" -ForegroundColor Green

# Start services
Write-Host "Step 5: Starting services..." -ForegroundColor Yellow
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to start services!" -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Services started" -ForegroundColor Green

# Wait for readiness
Write-Host "Step 6: Waiting for services (30 sec)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Check status
Write-Host "Step 7: Checking status..." -ForegroundColor Yellow
docker compose ps

# Database migrations
Write-Host "Step 8: Initializing database..." -ForegroundColor Yellow
$maxRetries = 5
$retry = 0
$success = $false

while ($retry -lt $maxRetries -and -not $success) {
    try {
        docker compose exec -T api bundle exec rails db:create 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            docker compose exec -T api bundle exec rails db:migrate 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  OK: Database initialized" -ForegroundColor Green
                $success = $true
            }
        }
    } catch {
        # Continue to retry
    }
    
    if (-not $success) {
        $retry++
        if ($retry -lt $maxRetries) {
            Write-Host "  Retry $retry of $maxRetries..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
}

if (-not $success) {
    Write-Host "  ERROR: Failed to initialize database" -ForegroundColor Red
    Write-Host "  Check logs: docker compose logs api" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment completed!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Available services:" -ForegroundColor Cyan
Write-Host "  Dashboard: http://localhost/dashboard" -ForegroundColor White
Write-Host "    Login: admin / Password: admin" -ForegroundColor Gray
Write-Host "  Health: http://localhost/health" -ForegroundColor White
Write-Host "  Sidekiq: http://localhost/sidekiq" -ForegroundColor White
Write-Host "  API: http://localhost:3000/api/v1/health" -ForegroundColor White
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Logs: docker compose logs -f" -ForegroundColor Gray
Write-Host "  Status: docker compose ps" -ForegroundColor Gray
Write-Host "  Stop: docker compose down" -ForegroundColor Gray
Write-Host ""
