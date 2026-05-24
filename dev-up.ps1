#!/usr/bin/env pwsh
# dev-up.ps1 — ローカル開発環境を一括起動
#   1. .env (backend / frontend) を作成（なければ .env.example をコピーし AUTH_ENABLED=false / port 15432 に書き換え）
#   2. postgres コンテナ pg-local を起動 (port 15432)
#   3. yarn install (node_modules が無ければ。Node 23 対応のため --ignore-engines)
#   4. prisma migrate deploy
#   5. backend (yarn start) / frontend (yarn dev) を別ウィンドウで起動
#
# 停止: docker stop pg-local  (起動した PowerShell ウィンドウは Ctrl+C で停止)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Invoke-Checked {
    param([string]$Label, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Label が失敗しました (exit $LASTEXITCODE)" }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend  = Join-Path $repoRoot 'backend\sandbox-backend'
$frontend = Join-Path $repoRoot 'frontend\sandbox-frontend'

function Ensure-EnvFile {
    param([string]$Dir, [hashtable]$Replacements)
    $envPath     = Join-Path $Dir '.env'
    $examplePath = Join-Path $Dir '.env.example'
    if (Test-Path $envPath) {
        Write-Host "[skip]    $envPath は既に存在"
        return
    }
    $content = Get-Content $examplePath -Raw -Encoding UTF8
    foreach ($k in $Replacements.Keys) {
        $content = $content.Replace($k, $Replacements[$k])
    }
    Set-Content -Path $envPath -Value $content -NoNewline -Encoding UTF8
    Write-Host "[create]  $envPath"
}

# ---- 1. .env ----
Ensure-EnvFile -Dir $backend -Replacements @{
    'postgresql://postgres:password@localhost:5432/mydb'                                  = 'postgresql://postgres:password@localhost:15432/mydb'
    'AUTH_ENABLED=true'                                                                   = 'AUTH_ENABLED=false'
    '{Auth0 ApplicationのBasic InformationのDomain (例: your-tenant.auth0.com)}'          = 'example.auth0.com'
}
Ensure-EnvFile -Dir $frontend -Replacements @{
    '{Auth0 ApplicationのBasic InformationのDomain (例: your-tenant.auth0.com)}' = 'example.auth0.com'
    '{Auth0 ApplicationのBasic InformationのClient ID}'                          = 'dummy-client-id'
    'VITE_AUTH_ENABLED=true'                                                     = 'VITE_AUTH_ENABLED=false'
}

# ---- 2. PostgreSQL ----
$pgName = 'pg-local'
$pgPort = 15432
$status = docker inspect $pgName --format '{{.State.Status}}' 2>$null
if (-not $status) {
    Write-Host "[run]     postgres コンテナ $pgName を作成・起動 (port $pgPort)"
    docker run -d --name $pgName `
        -e POSTGRES_USER=postgres `
        -e POSTGRES_PASSWORD=password `
        -e POSTGRES_DB=mydb `
        -p "${pgPort}:5432" `
        postgres:16 | Out-Null
} elseif ($status -eq 'running') {
    Write-Host "[skip]    postgres コンテナ $pgName は既に起動中"
} else {
    Write-Host "[start]   停止中の $pgName を起動"
    docker start $pgName | Out-Null
}

Write-Host "[wait]    postgres の準備完了を待機..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    docker exec $pgName pg_isready -U postgres -d mydb *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw "postgres が READY になりませんでした" }
Write-Host "[ok]      postgres ready"

# ---- 3. yarn install ----
if (-not (Test-Path (Join-Path $backend 'node_modules'))) {
    Write-Host "[install] backend (--ignore-engines)"
    Push-Location $backend
    try { Invoke-Checked 'backend yarn install' { yarn install --ignore-engines } } finally { Pop-Location }
} else {
    Write-Host "[skip]    backend node_modules は存在"
}
if (-not (Test-Path (Join-Path $frontend 'node_modules'))) {
    Write-Host "[install] frontend (--ignore-engines)"
    Push-Location $frontend
    try { Invoke-Checked 'frontend yarn install' { yarn install --ignore-engines } } finally { Pop-Location }
} else {
    Write-Host "[skip]    frontend node_modules は存在"
}

# ---- 4. Prisma generate + migrate ----
Push-Location $backend
try {
    Write-Host "[prisma]  generate"
    Invoke-Checked 'prisma generate' { yarn --ignore-engines prisma generate }
    Write-Host "[prisma]  migrate deploy"
    Invoke-Checked 'prisma migrate deploy' { yarn --ignore-engines prisma migrate deploy }
} finally { Pop-Location }

# ---- 5. 起動 ----
Write-Host "[start]   backend (yarn start) を別ウィンドウで起動"
Start-Process pwsh -ArgumentList '-NoExit', '-Command', "Set-Location '$backend'; yarn --ignore-engines start"

Write-Host "[start]   frontend (yarn dev) を別ウィンドウで起動"
Start-Process pwsh -ArgumentList '-NoExit', '-Command', "Set-Location '$frontend'; yarn --ignore-engines dev"

Write-Host ""
Write-Host "========================================"
Write-Host "  backend:  http://localhost:3000"
Write-Host "  frontend: http://localhost:5173"
Write-Host "========================================"
