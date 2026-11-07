# Cognito user pool: handles sign-in for the app.
# PtP is introduced to patients through their clinicians, so accounts are
# created by invitation only, not by anyone signing up on their own.

resource "aws_cognito_user_pool" "patients" {
  name                = "${local.name_prefix}-patients"
  deletion_protection = "ACTIVE" # stops the user pool from being deleted by accident

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Accounts are created by invitation (admin), never by open sign-up.
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # MFA is required for every account. For a health platform,
  # a password alone isn't enough to protect patient information.
  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# The app client the frontend uses to sign in.
resource "aws_cognito_user_pool_client" "app" {
  name         = "${local.name_prefix}-app"
  user_pool_id = aws_cognito_user_pool.patients.id

  # Browser and mobile apps can't keep a secret, so there isn't one.
  generate_secret = false

  # SRP sign-in means the password is never sent over the network directly.
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Don't reveal whether an email has an account (stops account enumeration).
  prevent_user_existence_errors = "ENABLED"

  # Short-lived tokens, so a stolen token stops working quickly.
  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  enable_token_revocation = true
}