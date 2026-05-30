# リモート state backend (azurerm / Blob Storage)
#
# storage_account_name などの環境依存値はここには書かず init 時に
# -backend-config で注入する (部分設定 / partial configuration)。
#   - CI:     GitHub Actions vars から -backend-config="storage_account_name=..." で渡す
#   - ローカル: backend.hcl を作成し terraform init -backend-config=backend.hcl
# 設定すべきキーの一覧は backend.hcl.example を参照。
#
# 初回のみ: bootstrap/ で Storage Account を作成 → 本ディレクトリで
#   terraform init -backend-config=backend.hcl -migrate-state
# によりローカル state をリモートへ移行する。
terraform {
  backend "azurerm" {
    # ストレージアカウントキーではなく Azure AD (OIDC) で認証する。
    # これにより GitHub Actions の plan/apply SP が listKeys 権限なしで state を読み書きできる。
    # ローカル実行時も az login 済みの AAD 認証が使われる (Storage Account Contributor 不要)。
    use_azuread_auth = true
  }
}
