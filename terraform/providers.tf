provider "aws" {
  region = var.aws_region

  # Every resource gets these tags automatically, so ownership, environment,
  # and data classification are always visible for auditing and cost tracking.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      DataClass   = "synthetic"
    }
  }
}