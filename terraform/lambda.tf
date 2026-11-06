# The intake Lambda function.
# It runs inside the private subnets, can only reach the database,
# and its role can only do the few things it actually needs.

locals {
  intake_function_name = "${local.name_prefix}-intake"
}

# Zip the handler so Lambda can run it. The zip goes in build/,
# which is gitignored since Terraform recreates it.
data "archive_file" "intake" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/intake.zip"
}

# The function's logs: kept for a year and encrypted with our KMS key.
resource "aws_cloudwatch_log_group" "intake" {
  name              = "/aws/lambda/${local.intake_function_name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

# Only the Lambda service can use this role.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "intake" {
  name               = "${local.intake_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# What the function is allowed to do. I wrote this instead of attaching
# AWS's managed policy, so every permission is visible and scoped.
data "aws_iam_policy_document" "intake_permissions" {
  # Exceptions (the pipeline checks that each one has a reason):
  #checkov:skip=CKV_AWS_111:Lambda creates and deletes its own VPC network interfaces, so their IDs are not known in advance. AWS's managed policy for Lambda VPC access grants these actions on all resources the same way.
  #checkov:skip=CKV_AWS_356:Same reason. The network interface and X-Ray actions apply to resources that do not exist until the function runs, so they cannot be listed ahead of time.

  # Write logs, but only to this function's own log group.
  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.intake.arn}:*"]
  }

  # Lambda needs these to connect to the VPC and send traces to X-Ray.
  # Lambda manages the network interfaces itself, so their IDs aren't known
  # ahead of time. AWS's own managed policy grants these on "*" too.
  statement {
    sid    = "VpcNetworkingAndTracing"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "intake" {
  name   = "intake-permissions"
  role   = aws_iam_role.intake.id
  policy = data.aws_iam_policy_document.intake_permissions.json
}

resource "aws_lambda_function" "intake" {
  function_name    = local.intake_function_name
  role             = aws_iam_role.intake.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.intake.output_path
  source_code_hash = data.archive_file.intake.output_base64sha256
  architectures    = ["arm64"]
  memory_size      = 256
  timeout          = 10

  # Caps how many copies can run at once. Limits cost and damage
  # if something goes wrong, like a flood of requests.
  reserved_concurrent_executions = 10

  # Runs in the private subnets with the Lambda security group,
  # so it can reach the database and nothing else.
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  # X-Ray tracing for debugging and monitoring. In a real deployment,
  # the private subnets would need a VPC endpoint for X-Ray to reach it.
  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.intake.name
  }

  # No secrets in environment variables. Those belong in Secrets Manager.
  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [aws_iam_role_policy.intake]
}