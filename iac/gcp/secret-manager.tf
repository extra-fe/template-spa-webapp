## DATABASE_URL シークレット
resource "google_secret_manager_secret" "database-url" {
  secret_id = "${var.app-name}-${var.environment}-database-url"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database-url" {
  secret      = google_secret_manager_secret.database-url.id
  secret_data = local.database-url
}

## AUTH0_DOMAIN シークレット
resource "google_secret_manager_secret" "auth0-domain" {
  secret_id = "${var.app-name}-${var.environment}-auth0-domain"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "auth0-domain" {
  secret      = google_secret_manager_secret.auth0-domain.id
  secret_data = var.auth0_domain
}

## AUTH0_AUDIENCE シークレット (LBのIPアドレスが決定後に設定するため、初期値はプレースホルダー)
resource "google_secret_manager_secret" "auth0-audience" {
  secret_id = "${var.app-name}-${var.environment}-auth0-audience"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "auth0-audience" {
  secret      = google_secret_manager_secret.auth0-audience.id
  secret_data = "https://${google_compute_global_address.lb-ip.address}"
}

## CORS_ORIGIN シークレット
resource "google_secret_manager_secret" "cors-origin" {
  secret_id = "${var.app-name}-${var.environment}-cors-origin"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "cors-origin" {
  secret      = google_secret_manager_secret.cors-origin.id
  secret_data = "https://${google_compute_global_address.lb-ip.address}"
}
