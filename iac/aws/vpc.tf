# アプリ全体を収容するVPC(DNSホスト名/解決を有効化してエンドポイント名前解決を許可)
resource "aws_vpc" "vpc" {
  assign_generated_ipv6_cidr_block = false
  cidr_block                       = var.vpc_cidr_block
  enable_dns_hostnames             = true
  enable_dns_support               = true
  tags = {
    "Name" = "${var.app-name}-${var.environment}"
  }
}

# インターネットゲートウェイ: パブリックサブネットから外部へ抜けるための出口
resource "aws_internet_gateway" "gw" {
  tags = {
    "Name" = "${var.app-name}-${var.environment}"
  }
  vpc_id = aws_vpc.vpc.id
}

# パブリックサブネット(AZ-1a): NAT GatewayなどIGW経由で外部公開するリソースを配置
resource "aws_subnet" "public1a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = var.subnet_public1a_cidr_block
  tags = {
    "Name" = "${var.app-name}-${var.environment}-public-1a"
  }
  vpc_id = aws_vpc.vpc.id
}

# プライベートサブネット(AZ-1a): ECS / RDS / Bastion等の内部リソース配置先
resource "aws_subnet" "private1a" {
  availability_zone = "${data.aws_region.current.region}a"
  cidr_block        = var.subnet_private1a_cidr_block
  tags = {
    "Name" = "${var.app-name}-${var.environment}-private-1a"
  }
  vpc_id = aws_vpc.vpc.id
}

# プライベートサブネット(AZ-1c): マルチAZ構成のためAZ-cにも同様のプライベートサブネットを用意
resource "aws_subnet" "private1c" {
  availability_zone = "${data.aws_region.current.region}c"
  cidr_block        = var.subnet_private1c_cidr_block
  tags = {
    "Name" = "${var.app-name}-${var.environment}-private-1c"
  }
  vpc_id = aws_vpc.vpc.id
}

# Elastic IP: NAT Gatewayに割り当てる固定パブリックIP
resource "aws_eip" "nat" {
  tags = {
    "Name" = "${var.app-name}-${var.environment}-nat-eip"
  }
  domain = "vpc"
}

# NAT Gateway: プライベートサブネットからのインターネット向け通信を中継
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1a.id
  tags = {
    "Name" = "${var.app-name}-${var.environment}-nat-public1a"
  }
}

# パブリック用ルートテーブル(IGW向け)
resource "aws_route_table" "custom" {
  tags = {
    "Name" = "${var.app-name}-${var.environment}-public"
  }
  vpc_id = aws_vpc.vpc.id
}

# パブリックルート: 0.0.0.0/0 を Internet Gateway 経由で外に出す
resource "aws_route" "custom" {
  route_table_id         = aws_route_table.custom.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# プライベート用ルートテーブル(NAT Gateway向け)
resource "aws_route_table" "main" {
  tags = {
    "Name" = "${var.app-name}-${var.environment}-private"
  }
  vpc_id = aws_vpc.vpc.id
}

# プライベートルート: 0.0.0.0/0 を NAT Gateway 経由で外に出す
resource "aws_route" "main" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}


# パブリックサブネット(1a)へパブリックルートテーブルを関連付け
resource "aws_route_table_association" "public1a" {
  route_table_id = aws_route_table.custom.id
  subnet_id      = aws_subnet.public1a.id
}

# プライベートサブネット(1a)へプライベートルートテーブルを関連付け
resource "aws_route_table_association" "private1a" {
  route_table_id = aws_route_table.main.id
  subnet_id      = aws_subnet.private1a.id
}
# プライベートサブネット(1c)へプライベートルートテーブルを関連付け
resource "aws_route_table_association" "private1c" {
  route_table_id = aws_route_table.main.id
  subnet_id      = aws_subnet.private1c.id
}

# VPCのメインルートテーブルをプライベート用に上書き(デフォルト動作を内部寄りに)
resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.vpc.id
  route_table_id = aws_route_table.main.id
}
