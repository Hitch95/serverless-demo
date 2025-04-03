import json
import boto3
import os
import uuid
from decimal import Decimal # Import Decimal for DynamoDB item serialization

# Helper function to handle Decimal types for JSON serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            # Convert Decimal to float or int
            if o % 1 > 0:
                return float(o)
            else:
                return int(o)
        return super(DecimalEncoder, self).default(o)

def handler(event, context):
    print("EVENT DEBUG:", json.dumps(event)) # Keep for debugging if needed

    table_name = os.environ.get("TABLE_NAME")
    # Important: Make sure ENDPOINT_URL is passed from Terraform
    endpoint_url = os.environ.get("ENDPOINT_URL") 

    if not table_name:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "TABLE_NAME environment variable not set"})
        }
    
    # If endpoint_url is not explicitly set for local dev/testing, boto3 uses default AWS endpoints
    # For LocalStack, it MUST be provided.
    dynamodb_args = {
        'region_name': 'us-east-1', # Or your desired region
        'aws_access_key_id': 'test',  # Only needed for specific localstack setups, often optional
        'aws_secret_access_key': 'test' # Only needed for specific localstack setups, often optional
    }
    if endpoint_url:
        dynamodb_args['endpoint_url'] = endpoint_url
        print(f"DEBUG: Connecting to DynamoDB endpoint: {endpoint_url}")
    else:
        print("DEBUG: ENDPOINT_URL not set, connecting to default AWS DynamoDB endpoint.")


    try:
        dynamodb = boto3.resource('dynamodb', **dynamodb_args)
        table = dynamodb.Table(table_name)
    except Exception as e:
         print(f"ERROR: Could not connect to DynamoDB. {str(e)}")
         return {
            "statusCode": 500,
            "body": json.dumps({"error": f"Failed to connect to DynamoDB: {str(e)}"})
        }


    # Normalize path and method extraction for different API Gateway payload versions
    route = event.get("rawPath") # HTTP API payload v2.0
    if route is None:
        route = event.get("path") # REST API or HTTP API payload v1.0
    
    method = event.get("requestContext", {}).get("http", {}).get("method") # HTTP API payload v2.0
    if method is None:
         method = event.get("httpMethod") # REST API or HTTP API payload v1.0

    if not route or not method:
         return {
            "statusCode": 400,
            "body": json.dumps({"error": "Could not determine route or method from event"})
        }

    print(f"DEBUG: Received request: Method={method}, Route={route}")

    # --- Route Handlers ---

    if route == "/hello" and method == "GET":
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Hello from Lambda!"})
        }

    elif route == "/contact" and method == "POST":
        try:
            body = json.loads(event.get("body", "{}"))
            # Basic validation
            if not body.get("email") or not body.get("name") or not body.get("message"):
                 return {
                    "statusCode": 400,
                    "body": json.dumps({"error": "Missing required fields: email, name, message"})
                }

            item = {
                "id": str(uuid.uuid4()),
                "email": body.get("email"),
                "name": body.get("name"),
                "message": body.get("message")
                # Add other fields as needed, ensure they match DynamoDB schema if strict
            }

            table.put_item(Item=item)
            print(f"DEBUG: Saved contact item with ID: {item['id']}")
            return {
                "statusCode": 201, # Use 201 Created for new resources
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"status": "saved", "id": item["id"]})
            }
        except json.JSONDecodeError:
             return {
                "statusCode": 400,
                "body": json.dumps({"error": "Invalid JSON body"})
            }
        except Exception as e:
            print(f"ERROR: Failed to save contact item. {str(e)}")
            return {
                "statusCode": 500,
                "body": json.dumps({"error": f"Failed to save contact: {str(e)}"})
            }

    # --- NEW: Handler for GET /contact ---
    elif route == "/contact" and method == "GET":
        try:
            # Scan operation can be expensive on large tables in real AWS
            # For smaller datasets or local testing, it's okay.
            response = table.scan()
            items = response.get('Items', [])
            
            # Handle potential pagination if needed in the future
            while 'LastEvaluatedKey' in response:
                response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
                items.extend(response.get('Items', []))

            print(f"DEBUG: Retrieved {len(items)} contact items.")
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                # Use the custom encoder to handle Decimals from DynamoDB
                "body": json.dumps(items, cls=DecimalEncoder) 
            }
        except Exception as e:
            print(f"ERROR: Failed to retrieve contact items. {str(e)}")
            return {
                "statusCode": 500,
                "body": json.dumps({"error": f"Failed to retrieve contacts: {str(e)}"})
            }

    # --- Default Fallback ---
    else:
        print(f"DEBUG: Route/Method not found: Method={method}, Route={route}")
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Route not found", "requested_path": route, "requested_method": method})
        }

