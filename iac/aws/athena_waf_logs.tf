# WAFログ用Glueデータベース
resource "aws_glue_catalog_database" "waf_logs" {
  name = "${replace(var.app-name, "-", "_")}_${var.environment}_waf_logs"
}

# WAFログ用Glueテーブル
# - WAF direct S3 logging は改行区切りJSON (NDJSON) 形式で出力
# - WAFバケットは us-east-1 にあるが、Athena Query Engine v3 のクロスリージョンS3クエリで
#   ap-northeast-1 のワークグループからそのままクエリ可能 (追加リージョン設定不要)
#
# S3パス: s3://<bucket>/AWSLogs/<account>/WAFLogs/us-east-1/<acl-name>/<yyyy>/<MM>/<dd>/<HH>/<mm>/
# partition projection は day(yyyy/MM/dd) 単位とし、HH/mm サブディレクトリは Athena が再帰スキャン
resource "aws_glue_catalog_table" "waf_logs" {
  name          = "waf_logs"
  database_name = aws_glue_catalog_database.waf_logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                     = "TRUE"
    "projection.enabled"           = "true"
    "projection.day.type"          = "date"
    "projection.day.range"         = "NOW-1YEARS,NOW"
    "projection.day.format"        = "yyyy/MM/dd"
    "projection.day.interval"      = "1"
    "projection.day.interval.unit" = "DAYS"
    "storage.location.template"    = "s3://${aws_s3_bucket.waf_logs.bucket}/AWSLogs/${data.aws_caller_identity.self.account_id}/WAFLogs/us-east-1/${aws_wafv2_web_acl.cloudfront.name}/$${day}/"
    "classification"               = "json"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.waf_logs.bucket}/AWSLogs/${data.aws_caller_identity.self.account_id}/WAFLogs/us-east-1/${aws_wafv2_web_acl.cloudfront.name}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = true # WAFログは gzip 圧縮で配信される

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    # WAFログのトップレベルフィールドと httpRequest ネスト構造
    # クエリ例:
    #   SELECT action, httprequest.clientip, httprequest.uri, COUNT(*) AS cnt
    #   FROM waf_logs
    #   WHERE day = '2024/05/17' AND action = 'BLOCK'
    #   GROUP BY action, httprequest.clientip, httprequest.uri
    #   ORDER BY cnt DESC
    columns {
      name = "timestamp"
      type = "bigint" # epoch milliseconds
    }
    columns {
      name = "formatversion"
      type = "int"
    }
    columns {
      name = "webaclid"
      type = "string"
    }
    columns {
      name = "terminatingruleid"
      type = "string" # "Default_Action" の場合はルールにマッチせずデフォルトアクションを実行
    }
    columns {
      name = "terminatingruletype"
      type = "string" # REGULAR / RATE_BASED / GROUP
    }
    columns {
      name = "action"
      type = "string" # ALLOW / BLOCK / COUNT / CAPTCHA / CHALLENGE
    }
    columns {
      name = "httpsourcename"
      type = "string" # "CloudFront"
    }
    columns {
      name = "httpsourceid"
      type = "string" # CloudFrontディストリビューションID
    }
    columns {
      name = "responsecodesent"
      type = "string"
    }
    columns {
      name = "httprequest"
      type = "struct<clientip:string,country:string,uri:string,args:string,httpversion:string,httpmethod:string,requestid:string>"
    }
    columns {
      name = "labels"
      type = "array<struct<name:string>>"
    }
    columns {
      # マッチしたルールグループの詳細。ブロック原因の調査に利用
      name = "rulegrouplist"
      type = "array<struct<ruleGroupId:string,terminatingRule:struct<ruleId:string,action:string,ruleMatchDetails:array<struct<conditionType:string,sensitivityLevel:string,location:string,matchedData:array<string>>>>,nonTerminatingMatchingRules:array<struct<ruleId:string,action:string>>,excludedRules:array<struct<exclusionType:string,ruleId:string>>>>"
    }
    columns {
      name = "nonterminatingmatchingrules"
      type = "array<struct<ruleId:string,action:string>>"
    }
  }
}

# Athenaワークグループ: WAFログクエリ用
# 注: クエリ対象S3バケットは us-east-1 だが、Athena v3 のクロスリージョンS3クエリにより
#     このワークグループ (ap-northeast-1) からそのままクエリ可能
resource "aws_athena_workgroup" "waf_logs" {
  name          = "${var.app-name}-${var.environment}-waf-logs"
  force_destroy = true

  configuration {
    # us-east-1 のバケットをクロスリージョンクエリするために v3 必須
    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }
}
