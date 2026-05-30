plugin "google" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

rule "terraform_typed_variables" {
  enabled = false
}
