## Bastion ホスト (Compute Engine + IAP Tunnel)
## IAP Tunnel 経由で SSH 接続するため、外部 IP は不要
resource "google_compute_instance" "bastion" {
  name         = "${var.app-name}-${var.environment}-bastion"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.private.id
    # 外部 IP なし (IAP Tunnel 経由でアクセス)
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  ## Cloud SQL Auth Proxy と PostgreSQL クライアントをインストール
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y postgresql-client wget

    # Cloud SQL Auth Proxy のインストール
    wget -q https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.3/cloud-sql-proxy.linux.amd64 -O /usr/local/bin/cloud-sql-proxy
    chmod +x /usr/local/bin/cloud-sql-proxy
  EOF

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [
    google_compute_firewall.allow-iap-ssh
  ]
}
