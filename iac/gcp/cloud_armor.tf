# Cloud Armor セキュリティポリシー: AWS WAF v2 (CloudFront scope) 相当
# 外部 Application LB にアタッチし、エッジで攻撃を遮断する。
#
# ルール構成 (AWS の WAF と概ね整合):
#   priority 1000: SQL Injection (OWASP ModSec CRS)         ≒ AWSManagedRulesCommonRuleSet (SQLi 部分)
#   priority 1100: XSS                                       ≒ AWSManagedRulesCommonRuleSet (XSS 部分)
#   priority 1200: Local File Inclusion                      ≒ AWSManagedRulesCommonRuleSet (LFI 部分)
#   priority 1300: Remote Code Execution                     ≒ AWSManagedRulesKnownBadInputsRuleSet
#   priority 1400: Method enforcement / protocol attack      ≒ AWSManagedRulesCommonRuleSet
#   priority 1500: Scanner detection                         ≒ 同上
#   priority 2000: /api/* レート制限 (5分/IP/2000リクエスト) ≒ RateLimitApi
#   priority 2147483647 (default): allow
#
# AWS WAF の AWSManagedRulesAmazonIpReputationList に直接対応するルールは無いが、
# Cloud Armor Adaptive Protection (priority 別管理) を併用する想定。
resource "google_compute_security_policy" "edge" {
  name        = "${var.app-name}-${var.environment}-edge-policy"
  description = "Edge WAF policy for ${var.app-name}-${var.environment}"
  type        = "CLOUD_ARMOR"

  # Adaptive Protection: ML ベースの異常検知 (AWS WAF にはない GCP 独自機能)
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  # ルール: SQL Injection
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "SQL Injection (preconfigured WAF)"
  }

  # ルール: XSS
  rule {
    action   = "deny(403)"
    priority = 1100
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Cross-site scripting (preconfigured WAF)"
  }

  # ルール: Local File Inclusion
  rule {
    action   = "deny(403)"
    priority = 1200
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Local File Inclusion (preconfigured WAF)"
  }

  # ルール: Remote Code Execution
  rule {
    action   = "deny(403)"
    priority = 1300
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Remote Code Execution (preconfigured WAF)"
  }

  # ルール: Protocol attack (HTTP smuggling, response splitting 等)
  rule {
    action   = "deny(403)"
    priority = 1400
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('protocolattack-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Protocol attack (preconfigured WAF)"
  }

  # ルール: Scanner detection
  rule {
    action   = "deny(403)"
    priority = 1500
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('scannerdetection-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Scanner detection (preconfigured WAF)"
  }

  # ルール: /api/* レート制限 (5分間で2000リクエスト/IP)
  # AWS の RateLimitApi (5分 2000req/IP) に揃える
  rule {
    action   = "rate_based_ban"
    priority = 2000
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 2000
        interval_sec = 300
      }
      ban_duration_sec = 600
    }
    match {
      expr {
        expression = "request.path.startsWith('/api/')"
      }
    }
    description = "Rate limit on /api/* (2000 req / 5min / IP)"
  }

  # デフォルトルール: 全てのトラフィックを許可
  # (priority 2147483647 = INT_MAX。固定値で1ポリシーに必ず1つ存在)
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule, higher priority overrides it"
  }

  # ログ: Cloud Armor のログは Cloud Logging に出力される
  # BigQuery への転送は bigquery_armor_logs.tf で sink 設定
  advanced_options_config {
    log_level = "VERBOSE"
  }
}
