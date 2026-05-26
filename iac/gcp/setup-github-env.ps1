# GitHub Environment "gcp-main" を作成し、 Terraform output の値を
# Variables / Secrets として登録するスクリプト。
#
# 前提:
#   - iac/gcp/ で terraform apply が完了している
#   - gh CLI でログイン済み (gh auth status で確認)
#
# 実行:
#   cd iac/gcp
#   ./setup-github-env.ps1
#
# 引数:
#   -Repo        : owner/repo 形式 (省略時は gh repo view から取得)
#   -Environment : Environment 名 (既定: gcp-main)

[CmdletBinding()]
param(
    [string]$Repo = "",
    [string]$Environment = "gcp-main"
)

$ErrorActionPreference = "Stop"

# Repo を gh から取得
if (-not $Repo) {
    $Repo = (gh repo view --json nameWithOwner --jq '.nameWithOwner').Trim()
}
Write-Host "Target repository : $Repo" -ForegroundColor Cyan
Write-Host "Target environment: $Environment" -ForegroundColor Cyan
Write-Host ""

# 1. Environment 作成 (既存なら no-op)
Write-Host "==> Creating environment '$Environment'..." -ForegroundColor Yellow
gh api `
    --method PUT `
    "/repos/$Repo/environments/$Environment" `
    --silent
Write-Host "    OK" -ForegroundColor Green
Write-Host ""

# 2. Variables 登録
Write-Host "==> Registering Variables..." -ForegroundColor Yellow
$variablesJson = (terraform output -raw github_actions_variables_json)
$variables     = $variablesJson | ConvertFrom-Json
foreach ($key in ($variables.PSObject.Properties.Name | Sort-Object)) {
    $value = [string]$variables.$key
    Write-Host "    - $key" -ForegroundColor Gray
    gh variable set $key `
        --env $Environment `
        --repo $Repo `
        --body $value | Out-Null
}
Write-Host "    OK" -ForegroundColor Green
Write-Host ""

# 3. Secrets 登録
Write-Host "==> Registering Secrets..." -ForegroundColor Yellow
$secretsJson = (terraform output -json github_actions_secrets)
$secrets     = $secretsJson | ConvertFrom-Json
foreach ($key in ($secrets.PSObject.Properties.Name | Sort-Object)) {
    $value = [string]$secrets.$key
    Write-Host "    - $key" -ForegroundColor Gray
    gh secret set $key `
        --env $Environment `
        --repo $Repo `
        --body $value | Out-Null
}
Write-Host "    OK" -ForegroundColor Green
Write-Host ""

Write-Host "Done. Verify at https://github.com/$Repo/settings/environments/$Environment" -ForegroundColor Cyan
