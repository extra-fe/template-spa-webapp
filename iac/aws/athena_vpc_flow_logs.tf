# Athenaクエリ結果格納用S3バケット(クエリのたびにCSV/メタデータがここに書き出される)
resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.app-name}-${var.environment}-athena-results-${random_string.suffix.result}"
  tags = {
    "Name" = "${var.app-name}-${var.environment}-athena-results"
  }
}

# パブリックアクセス全面ブロック
resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バージョニング無効化(他バケットと方針を揃える)
resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.bucket

  versioning_configuration {
    status = "Disabled"
  }
}

# 30日でクエリ結果を自動削除(再実行で再生成できるため長期保管不要)
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.bucket

  rule {
    id     = "expire-old-results"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

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

# Athenaワークグループ: クエリ結果の出力先を強制し、誤って別バケットへ書き出すのを防ぐ
resource "aws_athena_workgroup" "main" {
  name          = "${var.app-name}-${var.environment}"
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
    "Name" = "${var.app-name}-${var.environment}"
  }
}
