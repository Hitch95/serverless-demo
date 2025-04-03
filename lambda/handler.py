import json
import boto3
import os
import uuid

def handler(event, context):
    print("EVENT DEBUG:", json.dumps(event))

    table_name = os.environ.get("TABLE_NAME")
    endpoint_url = os.environ.get("ENDPOINT_URL")

    if not table_name or not endpoint_url:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Environment variables not configured"})
        }

    dynamodb = boto3.resource(
        'dynamodb',
        region_name='us-east-1',
        endpoint_url=endpoint_url,
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )
    table = dynamodb.Table(table_name)

    route = event.get("rawPath") or event.get("path") or ""
    method = (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod") or ""
    )

    if route == "/hello" and method == "GET":
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Hello from Lambda!"})
        }

    elif route == "/contact" and method == "POST":
        body = json.loads(event.get("body", "{}"))
        item = {
            "id": str(uuid.uuid4()),
            "email": body.get("email"),
            "name": body.get("name"),
            "message": body.get("message")
        }

        try:
            table.put_item(Item=item)
            return {
                "statusCode": 200,
                "body": json.dumps({"status": "saved", "id": item["id"]})
            }
        except Exception as e:
            return {
                "statusCode": 500,
                "body": json.dumps({"error": str(e)})
            }

    elif route == "/contact" and method == "GET":
        try:
            response = table.scan()
            items = response.get('Items', [])
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps(items)
            }
        except Exception as e:
            return {
                "statusCode": 500,
                "body": json.dumps({"error": str(e)})
            }

    else:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": "Not found", "path": route, "method": method})
        }
