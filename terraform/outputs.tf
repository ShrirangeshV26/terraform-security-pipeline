# Values other systems need after deployment, like the frontend
# (API URL, Cognito IDs) or the app (database endpoint, secret location).

output "api_endpoint" {
  description = "Base URL of the HTTP API."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito user pool."
  value       = aws_cognito_user_pool.patients.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito app client used by the frontend."
  value       = aws_cognito_user_pool_client.app.id
}

output "documents_bucket_name" {
  description = "Name of the documents bucket."
  value       = aws_s3_bucket.documents.bucket
}

output "db_endpoint" {
  description = "Hostname of the PostgreSQL database (reachable only from inside the VPC)."
  value       = aws_db_instance.postgres.address
}

# The ARN only says where the password is stored, not the password itself.
output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the database admin password."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}