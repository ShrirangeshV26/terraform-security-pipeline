# S3 bucket for patient documents (synthetic in this demo).
# It's locked down four ways: no public access, encrypted with our KMS key,
# versioned so nothing is lost by accident, and HTTPS-only.

resource "aws_s3_bucket" "documents" {
  # bucket_prefix adds a random suffix, since bucket names must be globally unique
  bucket_prefix = "${local.name_prefix}-docs-"
}

# Block every form of public access, even if someone later adds a public policy by mistake.
# This is the setting I turn off in the demo to show the pipeline catching it.
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt every object with our own KMS key instead of the default S3 key.
# bucket_key_enabled cuts down on KMS calls, which keeps costs lower.
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

# Keep old versions of files, so an accidental overwrite or delete can be undone.
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Reject any request that isn't over HTTPS, so data is always encrypted in transit.
data "aws_iam_policy_document" "documents_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.documents.arn,
      "${aws_s3_bucket.documents.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  policy = data.aws_iam_policy_document.documents_tls_only.json

  # Apply the public access block first, so the policy never lands on an open bucket.
  depends_on = [aws_s3_bucket_public_access_block.documents]
}

# Access logging: every request to the documents bucket (who read or wrote
# which file, and when) gets recorded in a separate log bucket.
# This is part of the audit trail for patient data.

resource "aws_s3_bucket_logging" "documents" {
  bucket        = aws_s3_bucket.documents.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "documents/"
}

# The bucket that stores the access logs.
resource "aws_s3_bucket" "access_logs" {
  bucket_prefix = "${local.name_prefix}-access-logs-"
}

# Same lockdown as the documents bucket: no public access, ever.
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket owner owns every object, so access is controlled only by policy (no ACLs).
resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 access log delivery only supports SSE-S3 encryption on the target bucket,
# not KMS. So this bucket uses AES256 instead of our KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Keep logs for a year, then delete them, so storage doesn't grow forever.
# The right retention period depends on PtP's compliance requirements.
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Only the S3 logging service can write here, and only logs that come from
# the documents bucket in this account. Everything has to use HTTPS.
data "aws_iam_policy_document" "access_logs" {
  statement {
    sid       = "AllowS3AccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/documents/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.documents.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}