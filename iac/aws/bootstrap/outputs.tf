output "tfstate_bucket" {
  value       = aws_s3_bucket.tfstate.id
  description = "親 iac/aws の backend.hcl に設定する bucket 名"
}

output "backend_config_hint" {
  description = "親 iac/aws で実行する terraform init -migrate-state 用の backend 設定値"
  value = {
    bucket = aws_s3_bucket.tfstate.id
    key    = "aws/terraform.tfstate"
    region = var.aws-region
  }
}
