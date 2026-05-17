# ECSログ用Glueデータベース
resource "aws_glue_catalog_database" "ecs_logs" {
  name = "${replace(var.app-name, "-", "_")}_${var.environment}_ecs_logs"
}

# ECSログ用Glueテーブル: FireLens(Fluent Bit)がS3へ書き込むJSON形式ログを定義
# partition projection により MSCK REPAIR TABLE 不要で日付パーティションを自動解決
resource "aws_glue_catalog_table" "ecs_logs" {
  name          = "ecs_logs"
  database_name = aws_glue_catalog_database.ecs_logs.name
  catalog_id    = data.aws_caller_identity.self.account_id
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                      = "TRUE"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.format"        = "yyyy/MM/dd"
    "projection.date.range"         = "NOW-1YEARS,NOW"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${aws_s3_bucket.ecs_logs.bucket}/ecs-logs/$${date}/"
    "classification"                = "json"
  }

  partition_keys {
    name = "date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.ecs_logs.bucket}/ecs-logs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = false

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "container_id"
      type = "string"
    }
    columns {
      name = "container_name"
      type = "string"
    }
    columns {
      name = "source"
      type = "string"
    }
    columns {
      name = "log"
      type = "string"
    }
    columns {
      name = "ecs_cluster"
      type = "string"
    }
    columns {
      name = "ecs_task_arn"
      type = "string"
    }
    columns {
      name = "ecs_task_definition"
      type = "string"
    }
  }
}

# Athenaワークグループ: ECSログクエリ用
resource "aws_athena_workgroup" "ecs_logs" {
  name          = "${var.app-name}-${var.environment}-ecs-logs"
  force_destroy = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }
}
