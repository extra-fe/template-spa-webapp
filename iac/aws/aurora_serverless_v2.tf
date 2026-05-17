# DBサブネットグループ: Auroraクラスタを配置する2AZのプライベートサブネット
resource "aws_db_subnet_group" "db_subnet_group" {
  name = "${var.app-name}-${var.environment}"
  subnet_ids = [
    aws_subnet.private1a.id,
    aws_subnet.private1c.id
  ]
}

# DBマスターパスワード: 16桁のランダム文字列で自動生成
resource "random_string" "db_password" {
  length           = 16
  special          = false
  override_special = "!#$&"
}

# DB接続文字列(DATABASE_URL)を組み立て: SSMパラメータに保存しECSタスクへ注入する
# connection_limit / pool_timeout は variables.tf で管理 (設定指針は README.md 参照)
locals {
  db_raw_password     = random_string.db_password.result
  db_encoded_password = urlencode(local.db_raw_password)
  database_url = join("",
    [
      "postgresql://",
      "${aws_rds_cluster.cluster.master_username}",
      ":",
      "${local.db_encoded_password}",
      "@",
      "${aws_rds_cluster.cluster.endpoint}",
      ":",
      "${aws_rds_cluster.cluster.port}",
      "/",
      "${aws_rds_cluster.cluster.database_name}",
      "?",
      "sslmode=require",
      "&connection_limit=${var.db-connection-limit}",
      "&pool_timeout=${var.db-pool-timeout}"
    ]
  )
}

# Aurora PostgreSQL Serverless v2 クラスタ
# - 利用がない時間帯は自動で一時停止 (seconds_until_auto_pause)
# - min_capacity=0 でゼロまでスケールダウン可能
resource "aws_rds_cluster" "cluster" {
  cluster_identifier         = "${var.app-name}-${var.environment}-db-cluster"
  engine                     = "aurora-postgresql"
  engine_mode                = "provisioned"
  engine_version             = "16.11"
  database_name              = replace("${var.app-name}${var.environment}db", "-", "")
  master_username            = replace("${var.app-name}${var.environment}dbadmin", "-", "")
  master_password_wo         = local.db_raw_password
  master_password_wo_version = 1
  storage_encrypted          = true
  db_subnet_group_name       = aws_db_subnet_group.db_subnet_group.name
  serverlessv2_scaling_configuration {
    max_capacity             = 1.0
    min_capacity             = 0.0
    seconds_until_auto_pause = 3600
  }
  vpc_security_group_ids = [
    aws_security_group.db.id,
  ]
  skip_final_snapshot = true
}

# Serverless v2 のDBインスタンス(クラスタへ紐付ける実体)
resource "aws_rds_cluster_instance" "instance" {
  identifier         = "${var.app-name}-${var.environment}-db-instance"
  cluster_identifier = aws_rds_cluster.cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.cluster.engine
  engine_version     = aws_rds_cluster.cluster.engine_version
}

# SSMパラメータストア(SecureString): DATABASE_URLをECSタスクのsecretsとして参照させる
resource "aws_ssm_parameter" "db_connection_string" {
  data_type        = "text"
  name             = "/${var.environment}/connection_strings/${var.app-name}"
  tier             = "Standard"
  type             = "SecureString"
  value_wo         = local.database_url
  value_wo_version = 2
}
