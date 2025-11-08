data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  instance_type               = "t2.micro"
  #key_name                    = "xxxxx" //セッションマネージャで接続するので、キーペア不要
  monitoring = false
  subnet_id  = aws_subnet.private1a.id
  tags = {
    "Name" = "${var.environment}-bastion",
  }
  tenancy = "default"
  vpc_security_group_ids = [
    aws_security_group.bastion.id,
  ]
  root_block_device {
    delete_on_termination = true
    volume_size           = 30
    volume_type           = "gp2"
  }

  # SSM Agentを確実に起動
  user_data = <<-EOF
              #!/bin/bash
              # SSM Agentをインストール
              sudo dnf install -y amazon-ssm-agent
              sudo systemctl start amazon-ssm-agent
              sudo systemctl enable amazon-ssm-agent
              EOF

  user_data_replace_on_change = true

  # VPCエンドポイントが完全に作成されてから起動
  depends_on = [
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages
  ]
  timeouts {}
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.environment}-bastion_profile"
  role = aws_iam_role.bastion.name
}

resource "aws_iam_role" "bastion" {
  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
          Sid = ""
        },
      ]
      Version = "2012-10-17"
    }
  )
  description          = "EC2 bastion"
  max_session_duration = 3600
  name                 = "${var.environment}-bastion-role"
  path                 = "/"
  tags = {
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
