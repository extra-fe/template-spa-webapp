# SSM用VPCインターフェイスエンドポイント
# プライベートサブネット内の踏み台EC2が、NAT/IGWを経由せずにSession Managerへ接続するため
resource "aws_vpc_endpoint" "ssm" {
  ip_address_type = "ipv4"
  policy = jsonencode(
    {
      Statement = [
        {
          Action    = "*"
          Effect    = "Allow"
          Principal = "*"
          Resource  = "*"
        },
      ]
    }
  )
  private_dns_enabled = true
  security_group_ids = [
    aws_security_group.ssm.id,
  ]
  service_name = "com.amazonaws.${data.aws_region.current.region}.ssm"
  subnet_ids = [
    aws_subnet.private1c.id,
  ]
  tags = {
    "Name" = "${var.environment}-ssm",
  }
  vpc_endpoint_type = "Interface"
  vpc_id            = aws_vpc.vpc.id
  dns_options {
    dns_record_ip_type = "ipv4"
  }
  timeouts {}
}

# Session Managerのメッセージ通信用VPCエンドポイント(SSM Agentが利用)
resource "aws_vpc_endpoint" "ssmmessages" {
  ip_address_type = "ipv4"
  policy = jsonencode(
    {
      Statement = [
        {
          Action    = "*"
          Effect    = "Allow"
          Principal = "*"
          Resource  = "*"
        },
      ]
    }
  )
  private_dns_enabled = true
  security_group_ids = [
    aws_security_group.ssm.id,
  ]
  service_name = "com.amazonaws.${data.aws_region.current.region}.ssmmessages"
  subnet_ids = [
    aws_subnet.private1c.id,
  ]
  tags = {
    "Name" = "${var.environment}-ssmmessages",
  }
  vpc_endpoint_type = "Interface"
  vpc_id            = aws_vpc.vpc.id
  dns_options {
    dns_record_ip_type = "ipv4"
  }
  timeouts {}
}

# EC2 MessagesのVPCエンドポイント(SSM AgentがEC2 APIメッセージのやりとりに使用)
resource "aws_vpc_endpoint" "ec2messages" {
  ip_address_type = "ipv4"
  policy = jsonencode(
    {
      Statement = [
        {
          Action    = "*"
          Effect    = "Allow"
          Principal = "*"
          Resource  = "*"
        },
      ]
    }
  )
  private_dns_enabled = true
  security_group_ids = [
    aws_security_group.ssm.id,
  ]
  service_name = "com.amazonaws.${data.aws_region.current.region}.ec2messages"
  subnet_ids = [
    aws_subnet.private1c.id,
  ]
  tags = {
    "Name" = "${var.environment}-ec2messages",
  }
  vpc_endpoint_type = "Interface"
  vpc_id            = aws_vpc.vpc.id
  dns_options {
    dns_record_ip_type = "ipv4"
  }
  timeouts {}
}

# ECR API用VPCエンドポイント: ECS FargateがECRのコントロールプレーンAPIへNATを経由せずアクセスするため
resource "aws_vpc_endpoint" "ecr_api" {
  ip_address_type     = "ipv4"
  private_dns_enabled = true
  security_group_ids = [
    aws_security_group.ssm.id,
  ]
  service_name = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
  subnet_ids = [
    aws_subnet.private1a.id,
    aws_subnet.private1c.id,
  ]
  tags = {
    "Name" = "${var.environment}-ecr-api",
  }
  vpc_endpoint_type = "Interface"
  vpc_id            = aws_vpc.vpc.id
  dns_options {
    dns_record_ip_type = "ipv4"
  }
}

# ECR DKR用VPCエンドポイント: ECS FargateがDockerイメージレイヤーをNATを経由せずPullするため
resource "aws_vpc_endpoint" "ecr_dkr" {
  ip_address_type     = "ipv4"
  private_dns_enabled = true
  security_group_ids = [
    aws_security_group.ssm.id,
  ]
  service_name = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
  subnet_ids = [
    aws_subnet.private1a.id,
    aws_subnet.private1c.id,
  ]
  tags = {
    "Name" = "${var.environment}-ecr-dkr",
  }
  vpc_endpoint_type = "Interface"
  vpc_id            = aws_vpc.vpc.id
  dns_options {
    dns_record_ip_type = "ipv4"
  }
}

# CloudWatch Logs用VPCエンドポイント: ECSコンテナログをNATを経由せずCloudWatch Logsへ送信するため
resource "aws_vpc_endpoint" "logs" {
  ip_address_type     = "ipv4"
  private_dns_enabled = true
  security_group_ids = [
    aws_security_group.ssm.id,
  ]
  service_name = "com.amazonaws.${data.aws_region.current.region}.logs"
  subnet_ids = [
    aws_subnet.private1a.id,
    aws_subnet.private1c.id,
  ]
  tags = {
    "Name" = "${var.environment}-logs",
  }
  vpc_endpoint_type = "Interface"
  vpc_id            = aws_vpc.vpc.id
  dns_options {
    dns_record_ip_type = "ipv4"
  }
}

# S3用VPCゲートウェイエンドポイント: ECRイメージレイヤー(S3格納)取得をNATを経由せず行うため
# GatewayタイプはSGではなくルートテーブルへの関連付けで制御し、追加費用なし
resource "aws_vpc_endpoint" "s3" {
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  vpc_id            = aws_vpc.vpc.id
  route_table_ids = [
    aws_route_table.main.id,
    aws_route_table.custom.id,
  ]
  tags = {
    "Name" = "${var.environment}-s3",
  }
}
