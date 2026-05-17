# AWS Backup: Auroraクラスタの長期バックアップ管理
# - 専用Backup Vault (KMSは aws/backup 管理キーを利用)
# - 日次スケジュール(02:00 JST)、30日間保持
# - 同一リージョンのみ(クロスリージョンコピーなし)
# - Aurora自動バックアップ(最大35日)とは別系統で、Vault単位でアクセス制御・保持を管理する

# Backup Vault: スナップショットの保管先(KMS暗号化キーを指定しない場合は aws/backup マネージドキー)
resource "aws_backup_vault" "aurora" {
  name = "${var.app-name}-${var.environment}-aurora-vault"
}

# IAMロール: AWS BackupサービスがRDSスナップショット操作を行うためのサービスロール
resource "aws_iam_role" "backup" {
  name = "AWSBackup-${var.app-name}-${var.environment}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# AWS管理ポリシー: バックアップ実行に必要な権限
resource "aws_iam_role_policy_attachment" "backup_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# AWS管理ポリシー: 復元に必要な権限(別ジョブで復元する際に利用)
resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup Plan: 日次02:00 JST、30日保持
# 注: start-stop-resources.tf で13:00 JSTに自動停止されるが、停止中Auroraクラスタも
#     スナップショット取得は可能(AWS Backupが内部でCreateDBClusterSnapshotを呼び出す)
resource "aws_backup_plan" "aurora" {
  name = "${var.app-name}-${var.environment}-aurora-backup-plan"

  rule {
    rule_name                    = "daily-30days"
    target_vault_name            = aws_backup_vault.aurora.name
    schedule                     = "cron(0 2 * * ? *)"
    schedule_expression_timezone = "Asia/Tokyo"
    start_window                 = 60
    completion_window            = 240

    lifecycle {
      delete_after = 30
    }
  }
}

# Backup Selection: 上記プランで保護するリソース(Auroraクラスタ)を指定
resource "aws_backup_selection" "aurora" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.app-name}-${var.environment}-aurora-selection"
  plan_id      = aws_backup_plan.aurora.id

  resources = [
    aws_rds_cluster.cluster.arn
  ]
}
