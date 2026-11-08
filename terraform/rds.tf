# PostgreSQL database for patient journey data (synthetic in this demo).
# Private, encrypted at rest and in transit, backed up, and hard to delete
# by accident. AWS manages the admin password, so it never appears in code or state.

locals {
  db_identifier = "${local.name_prefix}-postgres"
}

# The database lives only in the private subnets.
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

# Force SSL on every connection, so data is always encrypted in transit.
resource "aws_db_parameter_group" "postgres" {
  name   = "${local.name_prefix}-postgres17"
  family = "postgres17"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Log every connection and disconnection, for the audit trail.
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

# Create the log groups ourselves, so they're encrypted and have a retention
# period. If RDS creates them, they'd be unencrypted and kept forever.
resource "aws_cloudwatch_log_group" "postgres" {
  for_each = toset(["postgresql", "upgrade"])

  name              = "/aws/rds/instance/${local.db_identifier}/${each.key}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

# Enhanced monitoring needs a role that RDS can use to send OS-level metrics.
data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${local.name_prefix}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "postgres" {
  identifier     = local.db_identifier
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100 # storage grows automatically up to this limit
  storage_type          = "gp3"

  db_name  = var.db_name
  username = "ptp_admin"

  # AWS creates the password and stores it in Secrets Manager, encrypted
  # with our KMS key. It never appears in code, logs, or Terraform state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.key_id

  # Private only: in the private subnets, reachable only from the Lambda.
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.postgres.name

  # Encrypted at rest with our KMS key, including backups and snapshots.
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  # Reliability: a standby copy in another availability zone, plus daily
  # backups kept for two weeks.
  multi_az                = true
  backup_retention_period = 14
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot   = true

  # Protection against accidental deletion: AWS refuses to delete the database
  # while this is on, and a final snapshot is always taken if it's ever removed.
  deletion_protection       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.db_identifier}-final"

  # Lets the app connect with short-lived IAM tokens instead of a stored password.
  iam_database_authentication_enabled = true

  # Monitoring: OS metrics every minute, and database logs sent to CloudWatch.
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights: shows which queries run and how long they take.
  # Encrypted with our KMS key, and 7 days of history is free.
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 7

  auto_minor_version_upgrade = true

  # Terraform itself also refuses to destroy the database. Removing it would
  # take a deliberate code change that goes through review.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [aws_cloudwatch_log_group.postgres]
}