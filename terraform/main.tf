# Add GET method for /contact
resource "aws_api_gateway_method" "contact_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "GET"
  authorization = "NONE"
}

# Add integration for GET method
resource "aws_api_gateway_integration" "contact_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# Update Lambda environment variables
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
      TABLE_NAME  = aws_dynamodb_table.contacts.name
      ENDPOINT_URL = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr" # LocalStack endpoint
    }
  }
}

# Update deployment triggers
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_resource.contact.id,
      aws_api_gateway_method.hello.id,
      aws_api_gateway_method.contact.id,
      aws_api_gateway_method.contact_get.id,
      aws_api_gateway_integration.hello.id,
      aws_api_gateway_integration.contact.id,
      aws_api_gateway_integration.contact_get.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.hello,
    aws_api_gateway_integration.contact,
    aws_api_gateway_integration.contact_get
  ]
}
