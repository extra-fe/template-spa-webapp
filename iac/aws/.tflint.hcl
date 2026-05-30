plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# variables.tf の全変数に type を付けることは侵襲的な変更になるため無効化。
# 将来的に type を付ける際はこのルールを再度有効化すること。
rule "terraform_typed_variables" {
  enabled = false
}
