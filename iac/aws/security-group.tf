resource "aws_security_group" "alb" {
  name = "${var.app-name}-${var.environment}-internal-alb"
  tags = {
    "Name" = "internal-alb"
  }
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "alb_out" {
  security_group_id = aws_security_group.alb.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "ecs_service" {
  name = "${var.app-name}-${var.environment}-ecs-service"
  tags = {
    "Name" = "ecs-service"
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

resource "aws_security_group_rule" "ecs_service_in_alb" {
  security_group_id        = aws_security_group.ecs_service.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = var.api-expose-port
  to_port                  = var.api-expose-port
  source_security_group_id = aws_security_group.alb.id
  description              = "internal ALB target group"
}

resource "aws_security_group_rule" "ecs_service_out" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

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

resource "aws_security_group_rule" "alb_in" {
  security_group_id        = aws_security_group.alb.id
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = data.aws_security_group.cloudfront_vpc_origin.id
  description              = "CloudFront VPC Origin http"
}


resource "aws_security_group" "db" {
  name = "${var.app-name}-${var.environment}-db"
  tags = {
    "Name" = "db"
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

resource "aws_security_group_rule" "db_in_ecs_service" {
  security_group_id        = aws_security_group.db.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.ecs_service.id
  description              = "API(ECS Service)"
}

resource "aws_security_group_rule" "db_in_bastion" {
  security_group_id        = aws_security_group.db.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.bastion.id
  description              = "bastion"
}


resource "aws_security_group_rule" "db_out" {
  security_group_id = aws_security_group.db.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "bastion" {
  description = "bastion"
  name        = "${var.environment}-${var.app-name}-bastion"
  tags = {
    "Name" = "${var.environment}-${var.app-name}-bastion",
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

resource "aws_security_group_rule" "bastion_in_mypc" {
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 0
  to_port           = 65535
  cidr_blocks       = var.local-pc-ip-addresses
  description       = "my pc"
}

resource "aws_security_group_rule" "bastion_out" {
  security_group_id = aws_security_group.bastion.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}


resource "aws_security_group" "ssm" {
  description = "ssm"
  name        = "${var.environment}-${var.app-name}-ssm"
  tags = {
    "Name" = "${var.environment}-${var.app-name}-ssm",
  }
  vpc_id = aws_vpc.vpc.id
  timeouts {}
}

resource "aws_security_group_rule" "ssm_in" {
  security_group_id        = aws_security_group.ssm.id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.bastion.id
  description              = "ssm"
}

resource "aws_security_group_rule" "ssm_out" {
  security_group_id = aws_security_group.ssm.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}
