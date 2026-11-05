# Encryption key for the demo setup.
# One customer-managed key encrypts the S3 bucket, the database, its backups,
# and the database password secret. Using our own key (instead of the AWS
# default) means we control who can use it, and every use shows up in CloudTrail.

resource "aws_kms_key" "main" {
  description             = "Encrypts synthetic patient data at rest"
  enable_key_rotation     = true # AWS rotates the key material every year
  deletion_window_in_days = 30   # max waiting period, so a deleted key can still be recovered

  tags = {
    Name = "${local.name_prefix}-key"
  }
}

# A readable name for the key, so it's easy to find in the console.
resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}