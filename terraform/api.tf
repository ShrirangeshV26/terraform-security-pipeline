# HTTP API: the only public entry point. Every route needs a valid
# Cognito login token, and every request is logged.

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
}

# Checks the login token on every request before it reaches the Lambda.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  name             = "cognito"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app.id]
    issuer   = "https://${aws_cognito_user_pool.patients.endpoint}"
  }
}

# Connects the API to the intake Lambda.
resource "aws_apigatewayv2_integration" "intake" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.intake.invoke_arn
  payload_format_version = "2.0"
}

# POST /intake, protected by the Cognito authorizer.
resource "aws_apigatewayv2_route" "intake" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /intake"
  target             = "integrations/${aws_apigatewayv2_integration.intake.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Access logs: kept for a year and encrypted with our KMS key.
resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # Logs who called what and the result. It records the user's ID (sub),
  # never the request body, so no patient information ends up in logs.
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId   = "$context.requestId"
      sourceIp    = "$context.identity.sourceIp"
      requestTime = "$context.requestTime"
      routeKey    = "$context.routeKey"
      status      = "$context.status"
      userSub     = "$context.authorizer.claims.sub"
      latency     = "$context.responseLatency"
    })
  }

  # Rate limits protect the backend and keep costs predictable.
  default_route_settings {
    throttling_burst_limit   = 20
    throttling_rate_limit    = 10
    detailed_metrics_enabled = true
  }
}

# Lets API Gateway call the Lambda, but only for POST /intake on this API.
resource "aws_lambda_permission" "api_invoke" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.intake.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/POST/intake"
}