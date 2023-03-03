output "function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.mypy_wheels_dispatch.function_name
}

output "base_url" {
  description = "Base URL for API Gateway stage."
  value = aws_apigatewayv2_stage.api_gw_stage.invoke_url
}
