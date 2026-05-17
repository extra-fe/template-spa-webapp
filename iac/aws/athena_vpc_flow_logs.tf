# Glueデータベース: Athenaから参照されるデータカタログ
# 名前にハイフン不可のため var.app-name のハイフンをアンダースコアに変換
resource "aws_glue_catalog_database" "vpc_flow_logs" {
  name = "${replace(var.app-name, "-", "_")}_${var.environment}_vpc_flow_logs"
}

# VPCフローログ用Glueテーブル
# - 空白区切りのテキスト(LazySimpleSerDe)で14フィールドのデフォルトフォーマットを定義
# - partition projectionで date パーティションを動的解決(MSCK REPAIR / 手動addPartition不要)
resource "aws_glue_catalog_table" "vpc_flow_logs" {
  name          = "vpc_flow_logs"
  database_name = aws_glue_catalog_database.vpc_flow_logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                      = "TRUE"
    "classification"                = "csv"
    "skip.header.line.count"        = "1"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.range"         = "NOW-1YEARS,NOW"
    "projection.date.format"        = "yyyy/MM/dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${aws_s3_bucket.vpc_flow_log.bucket}/AWSLogs/${data.aws_caller_identity.self.account_id}/vpcflowlogs/${data.aws_region.current.region}/$${date}/"
  }

  partition_keys {
    name = "date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.vpc_flow_log.bucket}/AWSLogs/${data.aws_caller_identity.self.account_id}/vpcflowlogs/${data.aws_region.current.region}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim"          = " "
        "serialization.format" = " "
      }
    }

    # フィールド順序は VPC Flow Logs デフォルトフォーマット(v2)に一致させる
    columns {
      name = "version"
      type = "int"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "interface_id"
      type = "string"
    }
    columns {
      name = "srcaddr"
      type = "string"
    }
    columns {
      name = "dstaddr"
      type = "string"
    }
    columns {
      name = "srcport"
      type = "int"
    }
    columns {
      name = "dstport"
      type = "int"
    }
    columns {
      name = "protocol"
      type = "bigint"
    }
    columns {
      name = "packets"
      type = "bigint"
    }
    columns {
      name = "bytes"
      type = "bigint"
    }
    columns {
      name = "start"
      type = "bigint"
    }
    columns {
      name = "end"
      type = "bigint"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "log_status"
      type = "string"
    }
  }
}

# VPCフローログ専用Athenaワークグループ
# クエリ結果はALBログと共用の athena_results バケット(alb.tf)に出力
resource "aws_athena_workgroup" "vpc_flow_logs" {
  name          = "${var.app-name}-${var.environment}-vpc-flow-logs"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = {
    "Name" = "${var.app-name}-${var.environment}-vpc-flow-logs"
  }
}
