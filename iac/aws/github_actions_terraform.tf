# GitHub Actions 用 OIDC (terraform plan / apply)
#
# AWS が GitHub の OIDC トークンを信頼するための IAM OIDC Provider と、
# plan (read) / apply (write) それぞれ専用の IAM Role を作成する。
#
# plan  ロール: PR や workflow_dispatch から利用。ReadOnlyAccess + state bucket 読み取り。
# apply ロール: GitHub Environment "iac-apply" からのみ利用可能。AdministratorAccess。
#              apply は必須レビュアー承認後にのみ実行されることで安全を担保する。
#
# 登録が必要な GitHub Variables / Secrets は terraform output github_actions_terraform で確認。

# GitHub Actions の OIDC トークンを AWS で検証するための IAM Provider
# リージョンを跨ぐグローバルリソースのため、同一 AWS アカウント内で 1 つだけ作成する。
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub の OIDC エンドポイント TLS 証明書の thumbprint (2023 年以降 AWS 側が自動検証するため
  # 実質的に使われないが、terraform provider の必須フィールドとして記入する)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# ---------- plan 用 IAM Role ----------

resource "aws_iam_role" "terraform_plan" {
  name        = "${var.app-name}-${var.environment}-terraform-plan"
  description = "GitHub Actions terraform plan (ReadOnly)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # pull_request イベント (sub = repo:OWNER/REPO:pull_request) と
          # workflow_dispatch (sub = repo:OWNER/REPO:ref:refs/heads/main) を許可する。
          # apply 専用の "environment:iac-apply" は含まないため apply には使えない。
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github-repository-name}:pull_request",
              "repo:${var.github-repository-name}:ref:refs/heads/main",
            ]
          }
        }
      },
    ]
  })
}

# ReadOnlyAccess: describe/list/get 系を網羅。terraform plan が必要な全 AWS API を概ねカバー。
resource "aws_iam_role_policy_attachment" "terraform_plan_readonly" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# state バケットへの読み取りアクセス (ReadOnlyAccess には含まれる場合もあるが明示的に付与)
resource "aws_iam_role_policy" "terraform_plan_state" {
  name = "tfstate-read"
  role = aws_iam_role.terraform_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.app-name}-${var.environment}-tfstate-${data.aws_caller_identity.self.account_id}",
          "arn:aws:s3:::${var.app-name}-${var.environment}-tfstate-${data.aws_caller_identity.self.account_id}/*",
        ]
      },
    ]
  })
}

# ---------- apply 用 IAM Role ----------

resource "aws_iam_role" "terraform_apply" {
  name        = "${var.app-name}-${var.environment}-terraform-apply"
  description = "GitHub Actions terraform apply (AdministratorAccess / iac-apply environment only)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # GitHub Environment "iac-apply" が active なジョブのみ AssumeRole できる。
            # Environment に必須レビュアーを設定することで apply 前に承認を必須化する。
            "token.actions.githubusercontent.com:sub" = "repo:${var.github-repository-name}:environment:iac-apply"
          }
        }
      },
    ]
  })
}

# terraform apply は IAM リソース (Role/Policy/OIDC Provider 等) を作成するため
# AdministratorAccess が必要。
resource "aws_iam_role_policy_attachment" "terraform_apply_admin" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------- outputs ----------

output "github_actions_terraform" {
  description = "PR3 ワークフローに設定する GitHub Variables の値 (gh variable set で登録)"
  value = {
    TF_PLAN_ROLE_ARN_AWS  = aws_iam_role.terraform_plan.arn
    TF_APPLY_ROLE_ARN_AWS = aws_iam_role.terraform_apply.arn
    AWS_REGION            = data.aws_region.current.region
  }
}
