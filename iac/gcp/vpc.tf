## VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.app-name}-${var.environment}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

## パブリックサブネット
resource "google_compute_subnetwork" "public" {
  name                     = "${var.app-name}-${var.environment}-public"
  ip_cidr_range            = var.subnet-public-cidr-block
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

## プライベートサブネット
resource "google_compute_subnetwork" "private" {
  name                     = "${var.app-name}-${var.environment}-private"
  ip_cidr_range            = var.subnet-private-cidr-block
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

## Cloud Router (Cloud NAT用)
resource "google_compute_router" "router" {
  name    = "${var.app-name}-${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

## Cloud NAT (プライベートサブネットからのインターネットアクセス)
resource "google_compute_router_nat" "nat" {
  name                               = "${var.app-name}-${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

## Serverless VPC Access Connector (Cloud Run → VPC接続用)
resource "google_vpc_access_connector" "connector" {
  name          = "${var.app-name}-dev-conn"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.0.8.0/28"
  min_instances = 2
  max_instances = 3

  depends_on = [google_compute_network.vpc]
}

## Private Service Connection (Cloud SQL Private IP用)
resource "google_compute_global_address" "private-ip-range" {
  name          = "${var.app-name}-${var.environment}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private-vpc-connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private-ip-range.name]
}

## ファイアウォールルール: IAP からの SSH を許可 (Bastion用)
resource "google_compute_firewall" "allow-iap-ssh" {
  name    = "${var.app-name}-${var.environment}-allow-iap-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP の IP レンジ
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

## ファイアウォールルール: 内部通信を許可
resource "google_compute_firewall" "allow-internal" {
  name    = "${var.app-name}-${var.environment}-allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc-cidr-block]
}

## ファイアウォールルール: ヘルスチェックを許可 (LB用)
resource "google_compute_firewall" "allow-health-check" {
  name    = "${var.app-name}-${var.environment}-allow-health-check"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  # Google Cloud ヘルスチェックの IP レンジ
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}
