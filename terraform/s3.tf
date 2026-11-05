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