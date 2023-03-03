# https://learn.hashicorp.com/tutorials/terraform/lambda-api-gateway
terraform {
  required_providers {
  aws = {
    source = "hashicorp/aws"
    version = "~> 4.56.0"
  }
  archive = {
    source = "hashicorp/archive"
    version = "~> 2.3.0"
  }
  }
}

provider "aws" {
  region = var.aws_region
}

data "archive_file" "lambda_layer" {
  type = "zip"

  source_dir = "${path.module}/out/lambda_layer"
  output_path = "${path.module}/out/lambda_layer.zip"
}

resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name = "mypy_wheels_requests_deps"
  compatible_runtimes = ["python3.9"]

  filename = data.archive_file.lambda_layer.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_layer.output_path)
}

data "archive_file" "handler" {
  type = "zip"

  source_dir = "${path.module}/src"
  output_path = "${path.module}/out/src.zip"
}

resource "aws_lambda_function" "mypy_wheels_dispatch" {
  function_name  = "mypy_wheels_dispatch"
  role            = aws_iam_role.lambda_exec.arn

  handler = "lambda.lambda_handler"
  runtime = "python3.9"
  timeout = 10
  layers = [aws_lambda_layer_version.lambda_layer.arn]

  environment {
    variables = {
      repo = var.repo
      github_pat = var.github_pat
      sig_key = var.sig_key
      mail_source = var.mail_source
      mail_recipient = var.mail_recipient
    }
  }

  filename = data.archive_file.handler.output_path
  source_code_hash = filebase64sha256(data.archive_file.handler.output_path)
}

resource "aws_cloudwatch_log_group" "mypy_wheels_dispatch" {
  name = "/aws/lambda/${aws_lambda_function.mypy_wheels_dispatch.function_name}"
  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "mypy_wheels_dispatch_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "custom_lambda_policy" {
  statement {
    actions = [ "ses:SendEmail" ]
    resources = [ "*" ]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "custom_lambda_policy" {
  name = "${aws_lambda_function.mypy_wheels_dispatch.function_name}-policy"
  description = "Custom policy for ${aws_lambda_function.mypy_wheels_dispatch.function_name} lambda function"
  policy = data.aws_iam_policy_document.custom_lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "name" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.custom_lambda_policy.arn
}

resource "aws_apigatewayv2_api" "api_gw" {
  name          = "mypy_wheels_gateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "api_gw_stage" {
  api_id = aws_apigatewayv2_api.api_gw.id

  name = "dev"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 10
    throttling_burst_limit = 10
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_apigatewayv2_integration" "webhook" {
  api_id = aws_apigatewayv2_api.api_gw.id

  integration_uri    = aws_lambda_function.mypy_wheels_dispatch.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id = aws_apigatewayv2_api.api_gw.id

  route_key = "POST /webhook"
  target = "integrations/${aws_apigatewayv2_integration.webhook.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.api_gw.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mypy_wheels_dispatch.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api_gw.execution_arn}/*/*"
}
