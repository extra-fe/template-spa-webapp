# Cloud Monitoring アラートポリシー: AWS CloudWatch Alarms 相当
#
# 通知先: Pub/Sub トピック + Email チャネル (variables.tf の alert-notification-emails 使用)
# サブスクリプション (Slack/Lambda等) は Terraform 外で管理する想定 (AWS と同じ思想)
#
# 閾値マッピング (AWS 側 cloudwatch_alarms.tf と整合):
#   Cloud Run CPU使用率        > 80%
#   Cloud Run メモリ使用率     > 80%
#   Cloud SQL CPU使用率        > 80%
#   Cloud SQL コネクション数   > 70 (db-custom-1-3840 で最大100に対する警告)
#   Cloud SQL メモリ使用率     > 80%
#   Cloud SQL ディスク使用率   > 80%
#   Cloud SQL ディスク容量     > 100 GiB (コスト監視)

locals {
  alarm_eval_duration            = "120s" # 連続2回(60秒×2)を超えたら通知
  alarm_period                   = "60s"  # 評価間隔
  alarm_cpu_threshold_pct        = 0.8    # Cloud Run / Cloud SQL CPU 80%
  alarm_memory_util_pct          = 0.8
  alarm_disk_util_pct            = 0.8
  alarm_db_connections_threshold = 70
  alarm_db_volume_bytes          = 107374182400 # 100 GiB
}

# 全アラーム共通の通知先 Pub/Sub トピック (Terraform 外でサブスクリプションを管理)
resource "google_pubsub_topic" "alarms" {
  name = "${var.app-name}-${var.environment}-alarms"

  depends_on = [google_project_service.services]
}

# Pub/Sub 通知チャネル
resource "google_monitoring_notification_channel" "pubsub" {
  display_name = "${var.app-name}-${var.environment}-alarms-pubsub"
  type         = "pubsub"

  labels = {
    topic = google_pubsub_topic.alarms.id
  }

  user_labels = {
    app         = var.app-name
    environment = var.environment
  }

  depends_on = [google_pubsub_topic_iam_member.monitoring_publisher]
}

# Cloud Monitoring が Pub/Sub に publish するための IAM 付与
# service identity (vpc.tf で google_project_service_identity.monitoring) を介して
# SA を先回り作成しておくことで、初回 apply 時の "SA does not exist" エラーを回避
resource "google_pubsub_topic_iam_member" "monitoring_publisher" {
  topic  = google_pubsub_topic.alarms.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_project_service_identity.monitoring.email}"
}

# Email 通知チャネル (alert-notification-emails が設定されている場合のみ)
resource "google_monitoring_notification_channel" "email" {
  for_each     = toset(var.alert-notification-emails)
  display_name = "${var.app-name}-${var.environment}-email-${replace(each.value, "@", "-at-")}"
  type         = "email"

  labels = {
    email_address = each.value
  }
}

locals {
  notification_channels = concat(
    [google_monitoring_notification_channel.pubsub.id],
    [for ch in google_monitoring_notification_channel.email : ch.id],
  )
}

# ---------- Cloud Run ----------

resource "google_monitoring_alert_policy" "cloud_run_cpu_high" {
  display_name = "${var.app-name}-${var.environment}-run-cpu-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run CPU > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${google_cloud_run_v2_service.backend.name}\" AND metric.type = \"run.googleapis.com/container/cpu/utilizations\""
      duration        = local.alarm_eval_duration
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_cpu_threshold_pct

      aggregations {
        alignment_period   = local.alarm_period
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }

  notification_channels = local.notification_channels
  user_labels = {
    app         = var.app-name
    environment = var.environment
  }
}

resource "google_monitoring_alert_policy" "cloud_run_memory_high" {
  display_name = "${var.app-name}-${var.environment}-run-memory-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run memory > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${google_cloud_run_v2_service.backend.name}\" AND metric.type = \"run.googleapis.com/container/memory/utilizations\""
      duration        = local.alarm_eval_duration
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_memory_util_pct

      aggregations {
        alignment_period   = local.alarm_period
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }

  notification_channels = local.notification_channels
}

# ---------- Cloud SQL ----------

resource "google_monitoring_alert_policy" "sql_cpu_high" {
  display_name = "${var.app-name}-${var.environment}-sql-cpu-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL CPU > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.gcp-project-id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\""
      duration        = local.alarm_eval_duration
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_cpu_threshold_pct

      aggregations {
        alignment_period   = local.alarm_period
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

resource "google_monitoring_alert_policy" "sql_memory_high" {
  display_name = "${var.app-name}-${var.environment}-sql-memory-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL memory > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.gcp-project-id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/memory/utilization\""
      duration        = local.alarm_eval_duration
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_memory_util_pct

      aggregations {
        alignment_period   = local.alarm_period
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

resource "google_monitoring_alert_policy" "sql_connections_high" {
  display_name = "${var.app-name}-${var.environment}-sql-connections-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL connections > ${local.alarm_db_connections_threshold}"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.gcp-project-id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/postgresql/num_backends\""
      duration        = local.alarm_eval_duration
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_db_connections_threshold

      aggregations {
        alignment_period   = local.alarm_period
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channels
}

resource "google_monitoring_alert_policy" "sql_disk_high" {
  display_name = "${var.app-name}-${var.environment}-sql-disk-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL disk utilization > 80%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.gcp-project-id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/disk/utilization\""
      duration        = local.alarm_eval_duration
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_disk_util_pct

      aggregations {
        alignment_period   = local.alarm_period
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
}

resource "google_monitoring_alert_policy" "sql_disk_bytes_high" {
  display_name = "${var.app-name}-${var.environment}-sql-disk-bytes-high"
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL disk bytes > 100 GiB"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${var.gcp-project-id}:${google_sql_database_instance.main.name}\" AND metric.type = \"cloudsql.googleapis.com/database/disk/bytes_used\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = local.alarm_db_volume_bytes

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.notification_channels
}
