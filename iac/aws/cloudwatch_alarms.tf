# CloudWatchアラーム集約: ECS / Aurora の異常検知用
#
# 通知先: aws_sns_topic.alarms (本ファイルで作成)
# サブスクリプション(Email/Slack/Lambda等)は本Terraformでは作成せず、AWSコンソールから手動で登録する想定。

# アラーム閾値: 1ヶ所で管理し、ACU上限変更時等に調整しやすくする
# Aurora Serverless v2 の動的指標は ACU 連動で変化する点に注意。
#   - 1 ACU ≒ 2 GiBメモリ・最大接続数 約90 (DBInstanceClassMemory/9,531,392 = 約90)
#   - FreeLocalStorage は ACU 連動で数GiB〜
locals {
  alarm_eval_periods      = 2  # 連続2回しきい値を超えたら通知(瞬間スパイクの誤検知抑制)
  alarm_period_seconds    = 60 # メトリクス評価間隔(秒)
  alarm_cpu_threshold_pct = 80 # CPU使用率しきい値(ECS/Aurora共通)
  alarm_memory_util_pct   = 80 # ECS MemoryUtilization 使用率しきい値 (= 残20%で通知)
  alarm_acu_util_pct      = 80 # Aurora ACUUtilization (Serverless v2のCPU+メモリ複合指標)

  # Aurora Serverless v2 (max_capacity=1.0 ACU = 約2GiBメモリ) 想定
  alarm_aurora_freeable_memory_bytes  = 209715200    # 200 MiB を下回ったら通知(残10%)
  alarm_aurora_connections_threshold  = 70           # 1 ACU 最大約90に対する警告線
  alarm_aurora_free_local_storage     = 536870912    # 512 MiB を下回ったら通知
  alarm_aurora_volume_bytes_threshold = 107374182400 # 100 GiB を超えたら通知(コスト監視)
}

# 全アラーム共通の通知先SNSトピック
# サブスクライバ(Email/Slack/Lambda等)はAWSコンソールから手動登録する
resource "aws_sns_topic" "alarms" {
  name = "${var.app-name}-${var.environment}-alarms"
}

# ---------- ECS タスク(サービスレベル指標) ----------
# AWS/ECS 名前空間の CPUUtilization / MemoryUtilization は ECSサービスが標準で出力(Container Insights不要)。
# Dimensions は ClusterName + ServiceName。

# ECS CPU使用率 > 80%
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.app-name}-${var.environment}-ecs-cpu-high"
  alarm_description   = "ECSサービスのCPU使用率が${local.alarm_cpu_threshold_pct}%を超過"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_cpu_threshold_pct
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.service.name
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ECS メモリ使用率 > 80% (= メモリ残りが20%未満)
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.app-name}-${var.environment}-ecs-memory-high"
  alarm_description   = "ECSサービスのメモリ使用率が${local.alarm_memory_util_pct}%を超過(残り20%未満)"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_memory_util_pct
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = aws_ecs_service.service.name
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------- Aurora PostgreSQL Serverless v2 ----------
# DBClusterIdentifier または DBInstanceIdentifier をDimensionsに指定。
# - インスタンスレベル指標: CPUUtilization, FreeableMemory, DatabaseConnections, FreeLocalStorage, ACUUtilization
# - クラスタレベル指標   : VolumeBytesUsed

# Aurora コネクション枯渇(1 ACU上限 約90に対する警告)
resource "aws_cloudwatch_metric_alarm" "aurora_connections_high" {
  alarm_name          = "${var.app-name}-${var.environment}-aurora-connections-high"
  alarm_description   = "Auroraコネクション数が${local.alarm_aurora_connections_threshold}を超過(枯渇間近)"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_aurora_connections_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.instance.identifier
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Aurora CPU使用率 > 80%
resource "aws_cloudwatch_metric_alarm" "aurora_cpu_high" {
  alarm_name          = "${var.app-name}-${var.environment}-aurora-cpu-high"
  alarm_description   = "AuroraインスタンスのCPU使用率が${local.alarm_cpu_threshold_pct}%を超過"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_cpu_threshold_pct
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.instance.identifier
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Aurora ACU使用率 > 80% (Serverless v2のCPU/メモリ複合指標 — スケール上限張り付き検知)
resource "aws_cloudwatch_metric_alarm" "aurora_acu_high" {
  alarm_name          = "${var.app-name}-${var.environment}-aurora-acu-high"
  alarm_description   = "Aurora ACU使用率が${local.alarm_acu_util_pct}%を超過(max_capacity張り付き間近)"
  namespace           = "AWS/RDS"
  metric_name         = "ACUUtilization"
  statistic           = "Average"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_acu_util_pct
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.instance.identifier
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Aurora 利用可能メモリ < 200 MiB (max_capacity=1.0 ACU=約2GiB 想定 / 残10%)
resource "aws_cloudwatch_metric_alarm" "aurora_freeable_memory_low" {
  alarm_name          = "${var.app-name}-${var.environment}-aurora-freeable-memory-low"
  alarm_description   = "Aurora FreeableMemoryが${local.alarm_aurora_freeable_memory_bytes}バイトを下回った"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Average"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_aurora_freeable_memory_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.instance.identifier
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Aurora ローカル一時SSD残量 < 512 MiB (一時テーブル/ソート溢れの検知)
resource "aws_cloudwatch_metric_alarm" "aurora_free_local_storage_low" {
  alarm_name          = "${var.app-name}-${var.environment}-aurora-local-storage-low"
  alarm_description   = "Aurora FreeLocalStorageが${local.alarm_aurora_free_local_storage}バイトを下回った"
  namespace           = "AWS/RDS"
  metric_name         = "FreeLocalStorage"
  statistic           = "Minimum"
  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_aurora_free_local_storage
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.instance.identifier
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Aurora クラスタストレージ利用量 > 100 GiB (本体ストレージは128TiBまで自動拡張するため "残量低下" ではなく "利用量増大によるコスト監視" 用途)
resource "aws_cloudwatch_metric_alarm" "aurora_volume_bytes_high" {
  alarm_name          = "${var.app-name}-${var.environment}-aurora-volume-bytes-high"
  alarm_description   = "Auroraクラスタストレージが${local.alarm_aurora_volume_bytes_threshold}バイトを超過(コスト確認)"
  namespace           = "AWS/RDS"
  metric_name         = "VolumeBytesUsed"
  statistic           = "Maximum"
  period              = 300 # クラスタ指標は5分粒度で十分
  evaluation_periods  = local.alarm_eval_periods
  threshold           = local.alarm_aurora_volume_bytes_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.cluster.cluster_identifier
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
