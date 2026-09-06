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

$GithubToken = $env:GITHUB_TOKEN
$CacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "Building Custom Frappe + ERPNext + HRMS + POS Awesome Image" -ForegroundColor Cyan
Write-Host "Image Tag: $ImageTag"
if ($GithubToken) {
    Write-Host "GitHub Auth: Configured (Private repos accessible)"
} else {
    Write-Host "GitHub Auth: Anonymous (Public repos)"
}
Write-Host "=========================================================" -ForegroundColor Cyan

$env:DOCKER_BUILDKIT = "1"
$buildArgs = @(
    "build",
    "--build-arg", "FRAPPE_REPO=https://github.com/idibek-alimov/frappe.git",
    "--build-arg", "FRAPPE_BRANCH=version-15",
    "--build-arg", "GITHUB_TOKEN=$GithubToken",
    "--build-arg", "CACHEBUST=$CacheBust",
    "-t", $ImageTag,
    "-f", "Dockerfile",
    "."
)

docker @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Retrying build without BuildKit..." -ForegroundColor Yellow
    $env:DOCKER_BUILDKIT = "0"
    docker @buildArgs
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "Build completed successfully: $ImageTag" -ForegroundColor Green
Write-Host "Next step: Run .\scripts\push.ps1 to push to Docker Hub" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
