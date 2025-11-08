resource "aws_db_subnet_group" "db_subnet_group" {
  name = "${var.app-name}-${var.environment}"
  subnet_ids = [
    aws_subnet.private1a.id,
    aws_subnet.private1c.id
  ]
}

resource "random_string" "db_password" {
  length           = 16
  special          = false
  override_special = "!#$&"
}

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
      "sslmode=require"
    ]
  )
}

resource "aws_rds_cluster" "cluster" {
  cluster_identifier         = "${var.app-name}-${var.environment}-db-cluster"
  engine                     = "aurora-postgresql"
  engine_mode                = "provisioned"
  engine_version             = "16.6"
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

resource "aws_rds_cluster_instance" "instance" {
  identifier         = "${var.app-name}-${var.environment}-db-instance"
  cluster_identifier = aws_rds_cluster.cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.cluster.engine
  engine_version     = aws_rds_cluster.cluster.engine_version
}

resource "aws_ssm_parameter" "db_connection_string" {
  data_type        = "text"
  name             = "/${var.environment}/connection_strings/${var.app-name}"
  tier             = "Standard"
  type             = "SecureString"
  value_wo         = local.database_url
  value_wo_version = 1
}
