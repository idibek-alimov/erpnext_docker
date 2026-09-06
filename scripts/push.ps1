[CmdletBinding()]
param (
    [string]$ImageTag = ""
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

if (-not $ImageTag) {
    $ImageTag = if ($env:DOCKER_IMAGE) { $env:DOCKER_IMAGE } else { "idibek/frappe-custom:v15" }
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "Pushing Custom Image to Docker Hub: $ImageTag" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

Write-Host "Ensuring Docker login..."
docker login
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker login failed."
    exit 1
}

Write-Host "Pushing $ImageTag..."
docker push $ImageTag

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "Push completed successfully!" -ForegroundColor Green
Write-Host "Image is now available on Docker Hub: $ImageTag" -ForegroundColor Green
Write-Host "You can pull and run this on any machine using Docker Compose." -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
