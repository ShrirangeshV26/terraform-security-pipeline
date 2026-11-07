# Deployment safety tests.
# These run "terraform plan" against a mock AWS provider, so they need no AWS
# account or credentials. Each test fails if a change would make data loss or
# exposure more likely, even when the security scanners don't flag it.

mock_provider "aws" {
  # Data sources need realistic fake values for the plan to work.
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "archive" {}

# The database can't be deleted by accident, and if it's ever removed
# on purpose, a final backup is taken first.
run "database_cannot_be_deleted_by_accident" {
  command = plan

  assert {
    condition     = aws_db_instance.postgres.deletion_protection == true
    error_message = "Deletion protection must stay on for the database."
  }

  assert {
    condition     = aws_db_instance.postgres.skip_final_snapshot == false
    error_message = "A final snapshot must be taken if the database is ever removed."
  }
}

# Backups exist and the database survives an availability zone failure.
run "database_is_backed_up_and_highly_available" {
  command = plan

  assert {
    condition     = aws_db_instance.postgres.backup_retention_period >= 7
    error_message = "Database backups must be kept for at least 7 days."
  }

  assert {
    condition     = aws_db_instance.postgres.multi_az == true
    error_message = "The database must run in Multi-AZ mode."
  }
}

# The database never becomes public, and its data stays encrypted.
run "database_stays_private_and_encrypted" {
  command = plan

  assert {
    condition     = aws_db_instance.postgres.publicly_accessible == false
    error_message = "The database must never be publicly accessible."
  }

  assert {
    condition     = aws_db_instance.postgres.storage_encrypted == true
    error_message = "Database storage must stay encrypted."
  }
}

# Old versions of documents are kept, so an overwrite or delete can be undone.
run "documents_bucket_keeps_versions" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.documents.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must stay enabled on the documents bucket."
  }
}

# Audit logs are kept for at least a year.
run "audit_logs_are_kept_for_a_year" {
  command = plan

  assert {
    condition = alltrue([
      for lg in concat(
        [
          aws_cloudwatch_log_group.vpc_flow_logs,
          aws_cloudwatch_log_group.intake,
          aws_cloudwatch_log_group.api_access,
        ],
        values(aws_cloudwatch_log_group.postgres),
      ) : lg.retention_in_days >= 365
    ])
    error_message = "All log groups must keep logs for at least 365 days."
  }
}

# The encryption key rotates, and a deleted key can still be recovered.
run "kms_key_is_rotated_and_recoverable" {
  command = plan

  assert {
    condition     = aws_kms_key.main.enable_key_rotation == true
    error_message = "Key rotation must stay enabled."
  }

  assert {
    condition     = aws_kms_key.main.deletion_window_in_days == 30
    error_message = "The key deletion window must stay at 30 days, the maximum."
  }
}

# A typo in the environment name is rejected before anything runs.
run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "prd"
  }

  expect_failures = [var.environment]
}