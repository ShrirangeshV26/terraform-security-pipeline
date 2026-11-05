# TFLint settings.
# The "recommended" preset catches common Terraform mistakes (unused variables,
# missing version pins, untyped variables). The AWS plugin adds AWS-specific
# checks, like invalid instance types or deprecated arguments.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0" # pinned, same idea as pinning the GitHub Actions
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}