# Encryption key for the demo setup.
# One customer-managed key encrypts the S3 bucket, the database, its backups,
# the log groups, and the database password secret. Using our own key (instead
# of the AWS default) means we control who can use it, and every use shows up
# in CloudTrail.

resource "aws_kms_key" "main" {
  description             = "Encrypts synthetic patient data at rest"
  enable_key_rotation     = true # AWS rotates the key material every year
  deletion_window_in_days = 30   # max waiting period, so a deleted key can still be recovered
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "${local.name_prefix}-key"
  }
}

# A readable name for the key, so it's easy to find in the console.
resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}

data "aws_iam_policy_document" "kms" {
  # Exceptions (the pipeline checks that each one has a reason):
  #checkov:skip=CKV_AWS_109:This is a KMS key policy, where "*" means this key only. The root account statement is AWS's default key policy and is needed so the key can always be managed.
  #checkov:skip=CKV_AWS_111:Same reason. Key policy statements only apply to this key, and CloudWatch Logs access is limited by an encryption context condition.
  #checkov:skip=CKV_AWS_356
  # The account keeps full control of the key. This is AWS's default key
  # policy statement. Without it, nobody could manage the key once it exists.
  statement {
    sid       = "EnableAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch Logs needs to use the key to encrypt log groups.
  # The condition limits it to log groups in this account and region only.
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}