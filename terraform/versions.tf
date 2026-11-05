terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Remote state is configured per environment (S3 backend with locking).
  # CI runs `terraform init -backend=false`, so validation never touches real state.
  # See docs/architecture.md for the recommended backend setup.
}