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

# インターネットゲートウェイ: Regional NAT Gateway がVPC外部へ抜けるための出口
# (Regional NAT GatewayはAWSがマネージドな専用ルートテーブルを作成し、自動的にIGWへルートする)
resource "aws_internet_gateway" "gw" {
  tags = {
    "Name" = "${var.app-name}-${var.environment}"
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

# Regional NAT Gateway (automatic mode):
# - VPC内のENI出現を検知してAZ自動拡張、ワークロード縮退時は自動縮小
# - IPアドレス管理もAWSが自動で行うため EIP/サブネット指定は不要
# - publicサブネット不要(AWSが裏側でNAT専用の通信経路を構成)
resource "aws_nat_gateway" "nat" {
  availability_mode = "regional"
  connectivity_type = "public"
  vpc_id            = aws_vpc.vpc.id
  tags = {
    "Name" = "${var.app-name}-${var.environment}-nat-regional"
  }
  # AWS公式上、Regional NAT GatewayはAZ拡張に最大60分かかる仕様。
  # provider既定の10分では createタイムアウトしやすいため明示的に延長。
  timeouts {
    create = "60m"
    delete = "30m"
  }
}

# プライベート用ルートテーブル(Regional NAT Gateway向け)
resource "aws_route_table" "main" {
  tags = {
    "Name" = "${var.app-name}-${var.environment}-private"
  }
  vpc_id = aws_vpc.vpc.id
}

# プライベートルート: 0.0.0.0/0 を Regional NAT Gateway 経由で外に出す
# (単一NAT IDをAZをまたがる全プライベートサブネットで共有可能)
resource "aws_route" "main" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
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
