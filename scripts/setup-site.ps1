[CmdletBinding()]
param (
    [string]$SiteName = "",
    [string]$AdminPassword = "",
    [string]$DbRootPassword = ""
)

$ErrorActionPreference = "Stop"

# Navigate to the docker root directory (parent of scripts/)
$DockerDir = Split-Path -Parent $PSScriptRoot
Set-Location $DockerDir

# Load .env if present
$EnvFile = Join-Path $DockerDir ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $k = $parts[0].Trim()
            $v = $parts[1].Trim().Trim('"').Trim("'")
            if ($k -and -not [string]::IsNullOrEmpty($v)) {
                [Environment]::SetEnvironmentVariable($k, $v, "Process")
            }
        }
    }
}

# Resolve variables with fallbacks
if (-not $SiteName) {
    $SiteName = if ($env:SITE_NAME) { $env:SITE_NAME } else { "mysite.localhost" }
}
if (-not $AdminPassword) {
    $AdminPassword = if ($env:ADMIN_PASSWORD) { $env:ADMIN_PASSWORD } else { "admin_password" }
}
if (-not $DbRootPassword) {
    $DbRootPassword = if ($env:DB_ROOT_PASSWORD) { $env:DB_ROOT_PASSWORD } else { "mariadb_root_password" }
}
$HttpPort = if ($env:HTTP_PORT) { $env:HTTP_PORT } else { "8088" }

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Frappe Site Initializer (PowerShell for Windows)" -ForegroundColor Cyan
Write-Host "  Site Name : $SiteName"
Write-Host "  HTTP Port : $HttpPort"
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Bring up the stack if not running
$runningBackend = docker compose ps --status running -q backend
if (-not $runningBackend) {
    Write-Host "[setup] Starting Docker services..." -ForegroundColor Yellow
    docker compose up -d
}

# 2. Wait for MariaDB to be genuinely ready
Write-Host "[setup] Waiting for database to be ready..." -ForegroundColor Yellow
$dbReady = $false
for ($i = 1; $i -le 30; $i++) {
    $null = docker compose exec db mysqladmin ping -h localhost -u root -p"$DbRootPassword" --silent 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[setup] Database is ready." -ForegroundColor Green
        $dbReady = $true
        break
    }
    Write-Host "[setup] ... attempt $i/30, retrying in 3s"
    Start-Sleep -Seconds 3
}

if (-not $dbReady) {
    Write-Error "[setup] Database failed to become ready in time."
    exit 1
}

# 3. Ensure bench directory structure is present
docker compose exec -w /home/frappe/frappe-bench backend mkdir -p config/pids logs sites apps

# 4. Create Frappe site and install apps
Write-Host "[setup] Creating site '$SiteName' and installing apps..." -ForegroundColor Yellow
Write-Host "[setup] (This takes 2–5 minutes on first run)..."
docker compose exec -w /home/frappe/frappe-bench backend `
    bench new-site "$SiteName" `
        --admin-password "$AdminPassword" `
        --db-root-password "$DbRootPassword" `
        --mariadb-user-host-login-scope "%" `
        --install-app erpnext `
        --install-app hrms `
        --install-app posawesome `
        --set-default

# 5. Set default site in currentsite.txt
docker compose exec -w /home/frappe/frappe-bench backend `
    bash -c "echo '$SiteName' > sites/currentsite.txt"

# 6. Set default_site in common_site_config.json
docker compose exec -w /home/frappe/frappe-bench backend `
    bench set-config -g default_site "$SiteName"

# 7. Copy static assets
Write-Host "[setup] Copying static assets..." -ForegroundColor Yellow
docker compose exec -w /home/frappe/frappe-bench backend `
    bash -c "rm -rf sites/assets && cp -r assets_dist sites/assets"

# 8. Enable background scheduler
docker compose exec -w /home/frappe/frappe-bench backend `
    bench --site "$SiteName" enable-scheduler

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Site ready!" -ForegroundColor Green
Write-Host "  URL      : http://localhost:$HttpPort" -ForegroundColor Green
Write-Host "  Username : Administrator" -ForegroundColor Green
Write-Host "  Password : $AdminPassword" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
