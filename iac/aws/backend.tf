# リモート state backend (S3)
#
# bucket / key / region などの環境依存値は、ここには書かず init 時に
# -backend-config で注入する (部分設定 / partial configuration)。
#   - CI:     GitHub Actions vars/secrets から -backend-config="key=value" で渡す
#   - ローカル: backend.hcl を作成し terraform init -backend-config=backend.hcl
# 設定すべきキーの一覧は backend.hcl.example を参照。
#
# 初回のみ: bootstrap/ で state バケットを作成 → 本ディレクトリで
#   terraform init -backend-config=backend.hcl -migrate-state
# によりローカル state をリモートへ移行する。
terraform {
  backend "s3" {
    # use_lockfile = true で DynamoDB 不要の S3 ネイティブロックを使用 (TF 1.10+)。
    use_lockfile = true
    encrypt      = true
  }
}
