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
  service_name = "com.amazonaws.ap-northeast-1.ssm"
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
  service_name = "com.amazonaws.ap-northeast-1.ssmmessages"
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
  service_name = "com.amazonaws.ap-northeast-1.ec2messages"
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
