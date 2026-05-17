# ECSアプリケーションログ用S3バケット (Fluent Bit/FireLens経由で書き込む)
resource "aws_s3_bucket" "ecs_logs" {
  bucket        = "${var.app-name}-${var.environment}-ecs-logs-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_public_access_block" "ecs_logs" {
  bucket                  = aws_s3_bucket.ecs_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Standard → Standard-IA(31日) → Glacier(365日) で長期保存
resource "aws_s3_bucket_lifecycle_configuration" "ecs_logs" {
  bucket = aws_s3_bucket.ecs_logs.id
  rule {
    id     = "tiering"
    status = "Enabled"
    filter {}
    transition {
      days          = 31
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# カスタムFluentBitイメージ用ECRリポジトリ
# ヘルスチェック除外フィルタとCloudWatch Logs + S3 二重出力設定を焼き込んだイメージを格納する
resource "aws_ecr_repository" "fluent_bit" {
  name                 = "${var.environment}/fluent-bit"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = {}
}

# FireLensコンテナ(log_router)自身のログ用ロググループ
resource "aws_cloudwatch_log_group" "firelens" {
  name              = "/ecs/firelens/${var.app-name}-${var.environment}"
  retention_in_days = 7
}

# タスクロール: Fluent BitがCloudWatch Logsへ書き込む + S3へ書き込む権限
resource "aws_iam_role_policy" "ecs_task_firelens" {
  name = "firelens-output"
  role = aws_iam_role.ecs_task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.backend.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.ecs_logs.arn}/*"
      }
    ]
  })
}
