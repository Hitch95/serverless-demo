provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  token                       = "" # Optional, often not needed for LocalStack
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Define endpoints for LocalStack
  endpoints {
    # Ensure these URLs point to your running LocalStack instance/proxy
    lambda     = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr" 
    apigateway = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    iam        = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    dynamodb   = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr"
    sts        = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr" # Often needed too
  }
}

variable "localstack_endpoint" {
  description = "The base URL for LocalStack services"
  type        = string
  # Make sure this matches the URLs in the provider block
  default     = "http://ip10-0-6-4-cvn3an3hp11h42sqv29g-4566.direct.lab-boris.fr" 
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-contact-api-role" # More descriptive name
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
  # Add tags if desired
  # tags = {
  #   Environment = "development"
  #   Project     = "ContactAPI"
  # }
}

# NEW: Define specific permissions needed by the Lambda function
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-contact-policy"
  description = "IAM policy for Lambda to access the contacts DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:Scan",    # Action needed for GET /contact
          "dynamodb:PutItem"  # Action needed for POST /contact
          # Add other actions like GetItem, Query, UpdateItem, DeleteItem if needed later
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.contacts.arn # Grant access specifically to this table
      },
      # Add basic CloudWatch Logs permissions (Recommended for debugging)
      {
         Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
         ],
         Effect   = "Allow",
         Resource = "arn:aws:logs:*:*:*" # Adjust region/account if not using defaults
      }
    ]
  })
}

# NEW: Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_lambda_function" "api" {
  function_name = "contact-api-lambda" # More descriptive name
  handler       = "handler.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "lambda.zip" # Make sure this zip file contains the updated handler.py
  source_code_hash = filebase64sha256("lambda.zip")
  timeout       = 15 # Increase if needed for slower scans

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.contacts.name
      # NEW: Pass the DynamoDB endpoint URL for LocalStack
      # Using the variable defined above for consistency
      ENDPOINT_URL = "${var.localstack_endpoint}" 
    }
  }

  # Ensure Lambda is created after the role and policy attachment are done
  depends_on = [aws_iam_role_policy_attachment.lambda_dynamodb_attach]
}

resource "aws_dynamodb_table" "contacts" {
  name         = "contacts-${random_string.suffix.result}" # Add suffix to avoid name clashes
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # tags = {
  #   Environment = "development"
  #   Project     = "ContactAPI"
  # }
}

# Add a random suffix to avoid naming collisions on recreation
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "Contact API" # More descriptive name
  description = "API for managing contacts backed by Lambda and DynamoDB (LocalStack)"

  # NEW: Explicitly define binary media types if needed (usually not for JSON APIs)
  # binary_media_types = ["*/*"] 

  # NEW: Add endpoint configuration (useful for edge/regional) - optional for LocalStack usually
  # endpoint_configuration {
  #   types = ["REGIONAL"]
  # }
}

# /hello resource (remains the same)
resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

# /contact resource (remains the same)
resource "aws_api_gateway_resource" "contact" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "contact"
}

# Method for GET /hello (changed from ANY to GET for clarity)
resource "aws_api_gateway_method" "hello_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET" # Changed from ANY
  authorization = "NONE"
  # Consider adding API Key requirement if needed:
  # api_key_required = false 
}

# Method for POST /contact (remains the same)
resource "aws_api_gateway_method" "contact_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "POST"
  authorization = "NONE"
  # api_key_required = false
}

# --- NEW: Method for GET /contact ---
resource "aws_api_gateway_method" "contact_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "GET"
  authorization = "NONE" # Allows unauthenticated access as requested
  # api_key_required = false
}

# Integration for GET /hello
resource "aws_api_gateway_integration" "hello_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST" # Must be POST for AWS_PROXY Lambda integration
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# Integration for POST /contact
resource "aws_api_gateway_integration" "contact_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_post.http_method
  integration_http_method = "POST" # Must be POST for AWS_PROXY Lambda integration
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# --- NEW: Integration for GET /contact ---
resource "aws_api_gateway_integration" "contact_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_get.http_method # Connect to the GET method
  integration_http_method = "POST" # Must be POST for AWS_PROXY Lambda integration
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# Deployment - IMPORTANT: Update triggers and depends_on
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Trigger redeployment when any relevant API Gateway resource changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_resource.contact.id,
      aws_api_gateway_method.hello_get.id,
      aws_api_gateway_method.contact_post.id,
      aws_api_gateway_method.contact_get.id,      # NEW
      aws_api_gateway_integration.hello_get.id,
      aws_api_gateway_integration.contact_post.id,
      aws_api_gateway_integration.contact_get.id   # NEW
      # You might also include aws_lambda_function.api.source_code_hash here
      # if you want API changes to deploy when only Lambda code changes
      # aws_lambda_function.api.source_code_hash 
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  # Ensure deployment happens after integrations are set up
  depends_on = [
    aws_api_gateway_integration.hello_get,
    aws_api_gateway_integration.contact_post,
    aws_api_gateway_integration.contact_get # NEW
  ]
}

# Stage (remains mostly the same)
resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "dev" # Or "v1", "prod", etc.

  # Enable CloudWatch Logs for the stage (Recommended for debugging API Gateway itself)
  # access_log_settings {
  #   destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn # Need to create this log group resource
  #   format          = jsonencode({ ... standard format variables ... }) 
  # }

  # variables = { # Stage variables can be accessed in mapping templates, etc.
  #   lambdaFunctionName = aws_lambda_function.api.function_name
  # }

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Permission - Using wildcards in source_arn often covers all methods for a resource path
# Re-evaluate if specific permissions per method are needed later.
# The existing permissions likely cover the new GET method due to the `*/*/contact` source ARN pattern.
# If you encounter permission issues specifically for GET, you might need to adjust or add another permission block.
resource "aws_lambda_permission" "allow_apigw_hello" {
  statement_id  = "AllowExecutionFromAPIGatewayHelloAnyMethod" # Updated name
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  # This ARN allows any method (*) on any stage (*) for the /hello path
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/hello"
}

resource "aws_lambda_permission" "allow_apigw_contact" {
  statement_id  = "AllowExecutionFromAPIGatewayContactAnyMethod" # Updated name
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  # This ARN allows any method (*) on any stage (*) for the /contact path
  # This should cover both POST and the new GET method.
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/contact" 
}

# Output the API Invoke URL
output "api_invoke_url" {
  description = "URL to invoke the API Gateway stage"
  value       = aws_api_gateway_stage.stage.invoke_url
}
