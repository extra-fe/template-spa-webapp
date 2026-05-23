# ALB用SG: 内部ALBに割り当て(インバウンドはCloudFront VPC Originからのみ許可)
resource "aws_security_group" "alb" {
  name = "${var.app-name}-${var.environment}-internal-alb"
  tags = {
    "Name" = "internal-alb"
  }
  vpc_id = aws_vpc.vpc.id
}

# ALBアウトバウンド: ECSサービスのAPIポートのみ許可
resource "aws_security_group_rule" "alb_out" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = var.api-expose-port
  to_port                  = var.api-expose-port
  source_security_group_id = aws_security_group.ecs_service.id
  description              = "to ECS service"
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

# ECSアウトバウンド: HTTPS(VPCエンドポイント経由のECR/CloudWatch + NAT経由の外部SaaS)
resource "aws_security_group_rule" "ecs_service_out_https" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "egress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS to VPC endpoints and external SaaS (Auth0 etc.)"
}

# ECSアウトバウンド: AuroraへのPostgreSQL接続
resource "aws_security_group_rule" "ecs_service_out_db" {
  security_group_id        = aws_security_group.ecs_service.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.db.id
  description              = "to Aurora DB"
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

# 踏み台アウトバウンド: SSM VPCインターフェイスエンドポイントへのHTTPS
resource "aws_security_group_rule" "bastion_out_ssm" {
  security_group_id = aws_security_group.bastion.id
  type              = "egress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "SSM VPC endpoints"
}

# 踏み台アウトバウンド: DB接続(ポートフォワード・メンテ用)
resource "aws_security_group_rule" "bastion_out_db" {
  security_group_id        = aws_security_group.bastion.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.db.id
  description              = "to Aurora DB"
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

# SSMエンドポイントSGからのアウトバウンド: VPC内HTTPSのみ(エンドポイントはVPC内部で完結)
resource "aws_security_group_rule" "ssm_out" {
  security_group_id = aws_security_group.ssm.id
  type              = "egress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "response to VPC resources"
}
