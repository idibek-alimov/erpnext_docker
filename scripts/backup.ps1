[CmdletBinding()]
param (
    [string]$SiteName = ""
)

$ErrorActionPreference = "Stop"

$DockerDir = Split-Path -Parent $PSScriptRoot
Set-Location $DockerDir

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

if (-not $SiteName) {
    $SiteName = if ($env:SITE_NAME) { $env:SITE_NAME } else { "mysite.localhost" }
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "Backing up Site: $SiteName" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

docker compose exec -w /home/frappe/frappe-bench backend bench --site "$SiteName" backup --with-files

Write-Host ""
Write-Host "Backup completed. Backup files are stored in sites/$SiteName/private/backups inside the sites volume." -ForegroundColor Green
