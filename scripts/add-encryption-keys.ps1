# Add encryption keys to .env file

$keys = @"
ENCRYPTION_PRIMARY_KEY=35e8b7807e327614a3e5a6cebcd54f336efa2d4b74f3e57fcc49bb3e7e617538
ENCRYPTION_DETERMINISTIC_KEY=b88c16f7369c1c1b4f4121832559d5de98c25914965d1e50c2d835a5ddb07a04
ENCRYPTION_KEY_DERIVATION_SALT=1bb6067d0fac8b35ca2ba36a48be0abd7f7115661764f5045396370af3668335
"@

$envFile = ".env"
if (Test-Path $envFile) {
    $content = Get-Content $envFile -Raw
    if ($content -notmatch "ENCRYPTION_PRIMARY_KEY") {
        Add-Content -Path $envFile -Value "`n$keys"
        Write-Host "Encryption keys added to .env" -ForegroundColor Green
    } else {
        Write-Host "Encryption keys already exist in .env" -ForegroundColor Yellow
    }
} else {
    Write-Host ".env file not found!" -ForegroundColor Red
    exit 1
}




