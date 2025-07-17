import json
import os
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to process S3 object creation events,
    fetch object metadata, and store it in DynamoDB.
    """
    print(f"Received event: {json.dumps(event)}")

    # Get DynamoDB table name from environment variables *inside the function*.
    # This ensures it's read correctly during each invocation,
    # especially in test environments where env vars might be set dynamically.
    DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')

    if not DYNAMODB_TABLE_NAME:
        print("Error: DYNAMODB_TABLE_NAME environment variable not set.")
        return {
            'statusCode': 500,
            'body': json.dumps('DynamoDB table name not configured.')
        }

    # Initialize AWS clients *inside the function* to ensure they pick up
    # the correct (mocked or real) environment for each invocation.
    s3_client = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')

    try:
        # Get the S3 event record
        record = event['Records'][0]
        s3_info = record['s3']

        bucket_name = s3_info['bucket']['name']
        object_key = s3_info['object']['key']
        object_size = s3_info['object'].get('size', 0) # Get size, default to 0 if not present
        event_time = record['eventTime']

        print(f"Processing object: s3://{bucket_name}/{object_key}")

        # Fetch additional metadata using S3 head_object
        try:
            s3_object_metadata = s3_client.head_object(Bucket=bucket_name, Key=object_key)
            print(f"S3 Object Metadata: {s3_object_metadata}")

            # Extract relevant metadata
            last_modified = s3_object_metadata['LastModified'].isoformat()
            etag = s3_object_metadata['ETag'].strip('"') # ETag usually comes with quotes
            content_type = s3_object_metadata.get('ContentType', 'N/A')
            user_metadata = s3_object_metadata.get('Metadata', {}) # Custom user metadata

        except Exception as e:
            print(f"Error fetching S3 object metadata for {object_key}: {e}")
            # If head_object fails, use available info from the event
            last_modified = event_time
            etag = 'N/A'
            content_type = 'N/A'
            user_metadata = {}

        # Prepare item for DynamoDB
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        item = {
            'object_key': object_key, # Primary key
            'bucket_name': bucket_name,
            'size_bytes': object_size,
            'last_modified': last_modified,
            'etag': etag,
            'content_type': content_type, 
            'event_time': event_time,
            'user_metadata': json.dumps(user_metadata) # Store user metadata as JSON string
        }

        # Put item into DynamoDB
        table.put_item(Item=item)
        print(f"Successfully wrote metadata for {object_key} to DynamoDB table {DYNAMODB_TABLE_NAME}")

        return {
            'statusCode': 200,
            'body': json.dumps(f'Metadata for {object_key} stored successfully!')
        }

    except KeyError as e:
        print(f"Error: Missing key in event structure: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps(f'Invalid S3 event structure: {e}')
        }
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'An error occurred: {e}')
        }

