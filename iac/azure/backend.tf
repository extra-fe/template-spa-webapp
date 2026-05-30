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
    # azurerm backend は Blob リースによるロックを内蔵するため追加設定は不要。
    # use_azuread_auth は CI ワークフロー側の -backend-config で注入する
    # (ローカルはキー認証、CI は AAD 認証と使い分けるため backend.tf には書かない)。
  }
}
