output "tfstate_bucket" {
  value       = google_storage_bucket.tfstate.name
  description = "親 iac/gcp の backend.hcl に設定する bucket 名"
}

output "backend_config_hint" {
  description = "親 iac/gcp で実行する terraform init -migrate-state 用の backend 設定値"
  value = {
    bucket = google_storage_bucket.tfstate.name
    prefix = "gcp/terraform.tfstate"
  }
}
