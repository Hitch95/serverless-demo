provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  token                       = ""
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    lambda     = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    apigateway = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    iam        = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    dynamodb   = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "dynamodb_access" {
  name = "lambda_dynamodb_access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.contacts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

resource "aws_lambda_function" "api" {
  function_name = "hello-api"
  handler       = "handler.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
  timeout       = 15
  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.contacts.name
      ENDPOINT_URL = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    }
  }
}

resource "aws_dynamodb_table" "contacts" {
  name         = "contacts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "hello-api"
  description = "API REST simulée"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_resource" "contact" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "contact"
}

resource "aws_api_gateway_method" "hello" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "contact_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "contact_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hello" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_integration" "contact_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_integration" "contact_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# Force a new deployment every time
resource "random_uuid" "deployment_hash" {}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    # Add a random UUID to force deployment every time
    redeployment = random_uuid.deployment_hash.result
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.hello,
    aws_api_gateway_method.contact_post,
    aws_api_gateway_method.contact_get,
    aws_api_gateway_integration.hello,
    aws_api_gateway_integration.contact_post,
    aws_api_gateway_integration.contact_get
  ]
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "dev"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "allow_apigw_hello" {
  statement_id  = "AllowExecutionFromAPIGatewayHello"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/hello"
}

resource "aws_lambda_permission" "allow_apigw_contact" {
  statement_id  = "AllowExecutionFromAPIGatewayContact"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/contact"
}
