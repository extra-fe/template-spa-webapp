# CloudFrontアクセスログ用Glueデータベース
resource "aws_glue_catalog_database" "cloudfront_logs" {
  name = "${replace(var.app-name, "-", "_")}_${var.environment}_cloudfront_logs"
}

# CloudFrontアクセスログ用Glueテーブル
# - JSON形式 (output_format = "json" で配信)
# - フィールド名にハイフン・括弧を含むCloudFrontキーを JsonSerDe mapping で安全な列名へ変換
# - partition projection で年/月/日/時 パーティションを動的解決 (MSCK REPAIR不要)
#
# S3パス: s3://<bucket>/AWSLogs/<account>/CloudFront/<dist-id>/<yyyy>/<MM>/<dd>/<HH>/
resource "aws_glue_catalog_table" "cloudfront_logs" {
  name          = "cloudfront_access_logs"
  database_name = aws_glue_catalog_database.cloudfront_logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                     = "TRUE"
    "projection.enabled"           = "true"
    "projection.day.type"          = "date"
    "projection.day.range"         = "NOW-1YEARS,NOW"
    "projection.day.format"        = "yyyy/MM/dd"
    "projection.day.interval"      = "1"
    "projection.day.interval.unit" = "DAYS"
    "projection.hour.type"         = "integer"
    "projection.hour.range"        = "0,23"
    "projection.hour.digits"       = "2"
    "storage.location.template"    = "s3://${aws_s3_bucket.cloudfront_logs.bucket}/${aws_cloudfront_distribution.cdn.id}/$${day}/$${hour}/"
    "classification"               = "json"
  }

  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.cloudfront_logs.bucket}/${aws_cloudfront_distribution.cdn.id}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = false

    # JsonSerDe: CloudFrontフィールド名 (cs-method / cs(Host) 等) を
    # Hive列名 (cs_method / cs_host 等) へ mapping で変換
    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json"             = "true"
        "use.null.for.invalid.data"         = "true"
        "mapping.edge_location"             = "x-edge-location"
        "mapping.sc_bytes"                  = "sc-bytes"
        "mapping.c_ip"                      = "c-ip"
        "mapping.cs_method"                 = "cs-method"
        "mapping.cs_host"                   = "cs(Host)"
        "mapping.cs_uri_stem"               = "cs-uri-stem"
        "mapping.sc_status"                 = "sc-status"
        "mapping.cs_referer"                = "cs(Referer)"
        "mapping.cs_user_agent"             = "cs(User-Agent)"
        "mapping.cs_uri_query"              = "cs-uri-query"
        "mapping.cs_cookie"                 = "cs(Cookie)"
        "mapping.edge_result_type"          = "x-edge-result-type"
        "mapping.edge_request_id"           = "x-edge-request-id"
        "mapping.x_host_header"             = "x-host-header"
        "mapping.cs_protocol"               = "cs-protocol"
        "mapping.cs_bytes"                  = "cs-bytes"
        "mapping.time_taken"                = "time-taken"
        "mapping.x_forwarded_for"           = "x-forwarded-for"
        "mapping.ssl_protocol"              = "ssl-protocol"
        "mapping.ssl_cipher"                = "ssl-cipher"
        "mapping.edge_response_result_type" = "x-edge-response-result-type"
        "mapping.cs_protocol_version"       = "cs-protocol-version"
        "mapping.fle_status"                = "fle-status"
        "mapping.fle_encrypted_fields"      = "fle-encrypted-fields"
        "mapping.c_port"                    = "c-port"
        "mapping.time_to_first_byte"        = "time-to-first-byte"
        "mapping.edge_detailed_result_type" = "x-edge-detailed-result-type"
        "mapping.sc_content_type"           = "sc-content-type"
        "mapping.sc_content_len"            = "sc-content-len"
        "mapping.sc_range_start"            = "sc-range-start"
        "mapping.sc_range_end"              = "sc-range-end"
      }
    }

    # CloudFront 標準ログ全フィールド / JSON キーとの対応は上記 mapping パラメータを参照
    columns {
      name = "date"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "edge_location"
      type = "string"
    }
    columns {
      name = "sc_bytes"
      type = "bigint"
    }
    columns {
      name = "c_ip"
      type = "string"
    }
    columns {
      name = "cs_method"
      type = "string"
    }
    columns {
      name = "cs_host"
      type = "string"
    }
    columns {
      name = "cs_uri_stem"
      type = "string"
    }
    columns {
      name = "sc_status"
      type = "int"
    }
    columns {
      name = "cs_referer"
      type = "string"
    }
    columns {
      name = "cs_user_agent"
      type = "string"
    }
    columns {
      name = "cs_uri_query"
      type = "string"
    }
    columns {
      name = "cs_cookie"
      type = "string"
    }
    columns {
      name = "edge_result_type"
      type = "string"
    }
    columns {
      name = "edge_request_id"
      type = "string"
    }
    columns {
      name = "x_host_header"
      type = "string"
    }
    columns {
      name = "cs_protocol"
      type = "string"
    }
    columns {
      name = "cs_bytes"
      type = "bigint"
    }
    columns {
      name = "time_taken"
      type = "double"
    }
    columns {
      name = "x_forwarded_for"
      type = "string"
    }
    columns {
      name = "ssl_protocol"
      type = "string"
    }
    columns {
      name = "ssl_cipher"
      type = "string"
    }
    columns {
      name = "edge_response_result_type"
      type = "string"
    }
    columns {
      name = "cs_protocol_version"
      type = "string"
    }
    columns {
      name = "fle_status"
      type = "string"
    }
    columns {
      name = "fle_encrypted_fields"
      type = "string"
    }
    columns {
      name = "c_port"
      type = "int"
    }
    columns {
      name = "time_to_first_byte"
      type = "double"
    }
    columns {
      name = "edge_detailed_result_type"
      type = "string"
    }
    columns {
      name = "sc_content_type"
      type = "string"
    }
    columns {
      name = "sc_content_len"
      type = "bigint"
    }
    columns {
      name = "sc_range_start"
      type = "bigint"
    }
    columns {
      name = "sc_range_end"
      type = "bigint"
    }
  }
}

# Athenaワークグループ: CloudFrontログクエリ用
resource "aws_athena_workgroup" "cloudfront_logs" {
  name          = "${var.app-name}-${var.environment}-cloudfront-logs"
  force_destroy = true

  configuration {
    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }
}
