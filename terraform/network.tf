# Networking for the demo setup.
# Everything is private on purpose: no public subnets, no internet gateway.
# The only traffic allowed is Lambda talking to the database on port 5432.

# The VPC that holds everything. DNS is turned on so services can find
# each other by name (like the database endpoint).
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Two private subnets in different availability zones.
# RDS needs at least two zones, and it also means one zone going down
# doesn't take everything with it.
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false # nothing here should ever get a public IP

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
  }
}

# AWS creates a default security group in every VPC, and it allows traffic
# by default. Managing it here with no rules locks it down, so nothing
# can accidentally end up using it.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

# Security group for the Lambda function.
resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Lambda functions: outbound access to the database only"
  vpc_id      = aws_vpc.main.id
}

# Security group for the PostgreSQL database.
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "PostgreSQL: inbound access from Lambda only"
  vpc_id      = aws_vpc.main.id
}

# Lambda can only send traffic to the database, nowhere else.
# Using the security group as the target (instead of an IP range) means
# this keeps working even if IPs change.
resource "aws_vpc_security_group_egress_rule" "lambda_to_db" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "PostgreSQL to the database"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# The database only accepts connections from the Lambda security group.
# This is the rule I break on purpose in the demo (opening it to 0.0.0.0/0)
# to show the pipeline catching it.
resource "aws_vpc_security_group_ingress_rule" "db_from_lambda" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from Lambda"
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}