# ALB用SG: 内部ALBに割り当て(インバウンドはCloudFront VPC Originからのみ許可)
resource "aws_security_group" "alb" {
  name = "${var.app-name}-${var.environment}-internal-alb"
  tags = {
    "Name" = "internal-alb"
  }
  vpc_id = aws_vpc.vpc.id
}

# ALBアウトバウンド: 全外向け通信を許可(ECSへの転送等)
resource "aws_security_group_rule" "alb_out" {
  security_group_id = aws_security_group.alb.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

# ECSサービス用SG
resource "aws_security_group" "ecs_service" {
  name = "${var.app-name}-${var.environment}-ecs-service"
  tags = {
    "Name" = "ecs-service"
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

# ECSインバウンド: ALBからAPI公開ポート(例:3000)のみ許可
resource "aws_security_group_rule" "ecs_service_in_alb" {
  security_group_id        = aws_security_group.ecs_service.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = var.api-expose-port
  to_port                  = var.api-expose-port
  source_security_group_id = aws_security_group.alb.id
  description              = "internal ALB target group"
}

# ECSアウトバウンド: 全外向け通信を許可(NAT経由のSaaS呼び出し等)
resource "aws_security_group_rule" "ecs_service_out" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

# CloudFront VPC Origin専用の管理SGを参照(VPC Origin作成時にAWSが自動生成)
# このSGからのトラフィックだけをALBに通すために利用
data "aws_security_group" "cloudfront_vpc_origin" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
  filter {
    name   = "vpc-id"
    values = [aws_vpc.vpc.id]
  }
  depends_on = [aws_cloudfront_vpc_origin.alb]
}

# ALBインバウンド: CloudFront VPC OriginのSGからのHTTP(80)のみ許可
resource "aws_security_group_rule" "alb_in" {
  security_group_id        = aws_security_group.alb.id
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = data.aws_security_group.cloudfront_vpc_origin.id
  description              = "CloudFront VPC Origin http"
}


# DB(Aurora)用SG
resource "aws_security_group" "db" {
  name = "${var.app-name}-${var.environment}-db"
  tags = {
    "Name" = "db"
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}


# DBインバウンド: ECSサービスからのPostgreSQL(5432)接続を許可
resource "aws_security_group_rule" "db_in_ecs_service" {
  security_group_id        = aws_security_group.db.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.ecs_service.id
  description              = "API(ECS Service)"
}


# DBインバウンド: 踏み台EC2からのPostgreSQL(5432)接続を許可(運用時のメンテ用)
resource "aws_security_group_rule" "db_in_bastion" {
  security_group_id        = aws_security_group.db.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.bastion.id
  description              = "bastion"
}


# DBアウトバウンド: 全外向け許可
resource "aws_security_group_rule" "db_out" {
  security_group_id = aws_security_group.db.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

# 踏み台EC2用SG
resource "aws_security_group" "bastion" {
  description = "bastion"
  name        = "${var.environment}-${var.app-name}-bastion"
  tags = {
    "Name" = "${var.environment}-${var.app-name}-bastion",
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

# 踏み台インバウンド: 開発者ローカルPCのIPからのみ全ポート許可
# (Session Manager運用が前提のため通常は不要だが、ポートフォワード補助用)
resource "aws_security_group_rule" "bastion_in_mypc" {
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 0
  to_port           = 65535
  cidr_blocks       = var.local-pc-ip-addresses
  description       = "my pc"
}

# 踏み台アウトバウンド: 全外向け許可(SSMエンドポイント・DB等への通信用)
resource "aws_security_group_rule" "bastion_out" {
  security_group_id = aws_security_group.bastion.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}


# SSM用VPCエンドポイント向けSG(Session Manager等のためのインターフェイスエンドポイントに付与)
resource "aws_security_group" "ssm" {
  description = "ssm"
  name        = "${var.environment}-${var.app-name}-ssm"
  tags = {
    "Name" = "${var.environment}-${var.app-name}-ssm",
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

# SSMエンドポイントへのインバウンド: VPC内部からのHTTPS(443)のみ許可
resource "aws_security_group_rule" "ssm_in" {
  security_group_id = aws_security_group.ssm.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "ssm"
}

# SSMエンドポイントSGからのアウトバウンド: 全許可
resource "aws_security_group_rule" "ssm_out" {
  security_group_id = aws_security_group.ssm.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}
