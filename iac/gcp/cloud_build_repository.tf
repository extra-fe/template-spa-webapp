# Cloud Build GitHub Connection に対する Repository リンク
#
# Cloud Build GitHub App (2nd gen) で承認済みの Connection に対して、
# 個別の GitHub リポジトリをリンクする (= Repository リソースを作成する) 処理。
# トリガーが repository_event_config で参照するためにはこのリンクが必須。
#
# 前提:
#   - Cloud Build > Repositories > Connections で Connection 自体は Console で承認済み
#     (Connection は GitHub OAuth 認可が必要なため Terraform で完結できない)
#   - 承認後の Connection リソース名を var.cloudbuild-github-connection に設定済み
# Connection リソース名から接続名のみを抽出
# 例: projects/PROJECT/locations/REGION/connections/github1 → github1
locals {
  cloudbuild_connection_name = var.cloudbuild-github-connection == "" ? "" : regex("connections/([^/]+)$", var.cloudbuild-github-connection)[0]
}

resource "google_cloudbuildv2_repository" "main" {
  count             = var.cloudbuild-github-connection == "" ? 0 : 1
  location          = var.gcp-region
  name              = replace(var.github-repository-name, "/", "-")
  parent_connection = local.cloudbuild_connection_name
  remote_uri        = "https://github.com/${var.github-repository-name}.git"
}
