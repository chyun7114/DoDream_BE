param(
    [ValidateSet("S", "M", "L")]
    [string]$Scale = "S",
    [string]$Container = "dodream-mysql",
    [string]$Database = "dodreamdb",
    [string]$User = "root",
    [string]$Password = "1234"
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "run-seed.sql"
if (-not (Test-Path $scriptPath)) {
    throw "Seed script not found: $scriptPath"
}

$prefix = "SET @seed_scale = '$Scale';`n"
$sql = $prefix + (Get-Content -Raw -Path $scriptPath)

$cmd = @(
    "exec", "-i", $Container,
    "mysql",
    "--default-character-set=utf8mb4",
    "-u$User",
    "-p$Password",
    $Database
)
$sql | docker @cmd

if ($LASTEXITCODE -ne 0) {
    throw "Seeding failed with exit code $LASTEXITCODE"
}

Write-Host "Seed completed with scale: $Scale"
