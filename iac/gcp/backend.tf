# リモート state backend (GCS)
#
# bucket などの環境依存値はここには書かず init 時に -backend-config で注入する
# (部分設定 / partial configuration)。
#   - CI:     GitHub Actions vars から -backend-config="bucket=..." で渡す
#   - ローカル: backend.hcl を作成し terraform init -backend-config=backend.hcl
# 設定すべきキーの一覧は backend.hcl.example を参照。
#
# 初回のみ: bootstrap/ で state バケットを作成 → 本ディレクトリで
#   terraform init -backend-config=backend.hcl -migrate-state
# によりローカル state をリモートへ移行する。
terraform {
  backend "gcs" {
    # GCS backend はロックを内蔵するため追加設定は不要。
  }
}
