import boto3
import os
import uuid
import json
import sys
from moto import mock_aws # Import mock_aws
from datetime import datetime # Import datetime for event timestamp

# Add the lambda directory to the Python path for importing handler
# This needs to be done before the import statement for the handler
current_dir = os.path.dirname(os.path.abspath(__file__))
lambda_dir = os.path.join(current_dir, '..', 'lambda')
sys.path.append(lambda_dir)

# Now import the lambda handler


# Define constants for mocked environment
MOCKED_S3_BUCKET_NAME = "my-mocked-s3-upload-bucket"
MOCKED_DYNAMODB_TABLE_NAME = "S3ObjectMetadata"
MOCKED_AWS_REGION = "us-east-1" # Moto typically defaults to us-east-1 for mocking

@mock_aws
def test_s3_lambda_dynamodb_integration():
    """
    Executes the integration test using mocked AWS services:
    1. Sets up mocked S3 and DynamoDB.
    2. Uploads a unique test file to the mocked S3.
    3. Manually constructs an S3 event and calls the Lambda handler.
    4. Verifies the metadata in the mocked DynamoDB.
    """
    print(f"\n--- Starting Integration Test with @mock_aws ---")
    print(f"Mocked S3 Bucket: {MOCKED_S3_BUCKET_NAME}")
    print(f"Mocked DynamoDB Table: {MOCKED_DYNAMODB_TABLE_NAME}")
    print(f"Mocked AWS Region: {MOCKED_AWS_REGION}")

    # Initialize mocked AWS clients
    s3_client = boto3.client('s3', region_name=MOCKED_AWS_REGION)
    dynamodb_client = boto3.client('dynamodb')
    # 1. Create mocked S3 bucket
    print(f"Creating mocked S3 bucket: {MOCKED_S3_BUCKET_NAME}...")
    s3_client.create_bucket(Bucket=MOCKED_S3_BUCKET_NAME)
    print("Mocked S3 bucket created.")

    # 2. Create mocked DynamoDB table
    print(f"Creating mocked DynamoDB table: {MOCKED_DYNAMODB_TABLE_NAME}...")
    dynamodb_client.create_table(
        TableName=MOCKED_DYNAMODB_TABLE_NAME,
        KeySchema=[
            {
                'AttributeName': 'object_key',
                'KeyType': 'HASH'
            }
        ],
        AttributeDefinitions=[
            {
                'AttributeName': 'object_key',
                'AttributeType': 'S'
            }
        ],
        BillingMode='PAY_PER_REQUEST'
    )
    # Wait for table to be active in mocked environment (optional but good practice)
    waiter = dynamodb_client.get_waiter('table_exists')
    waiter.wait(TableName=MOCKED_DYNAMODB_TABLE_NAME)
    print("Mocked DynamoDB table created.")

    # Set environment variable for Lambda handler (it expects this)
    os.environ['DYNAMODB_TABLE_NAME'] = MOCKED_DYNAMODB_TABLE_NAME

    test_file_content = f"This is an automated test file. Unique ID: {uuid.uuid4()}"
    test_file_key = f"e2e-tests/test-file-{uuid.uuid4()}.txt"

    try:
        # 3. Put object into mocked S3
        print(f"Putting object '{test_file_key}' into mocked s3://{MOCKED_S3_BUCKET_NAME}...")
        s3_client.put_object(
            Bucket=MOCKED_S3_BUCKET_NAME,
            Key=test_file_key,
            Body=test_file_content,
            ContentType='text/plain',
            Metadata={'test_metadata': 'mocked_value'}
        )
        print("Object put into mocked S3 successfully.")

        # 4. Manually construct S3 event and call Lambda handler
        # This simulates the S3 trigger
        mock_s3_event = {
            "Records": [
                {
                    "eventVersion": "2.1",
                    "eventSource": "aws:s3",
                    "awsRegion": MOCKED_AWS_REGION,
                    "eventTime": datetime.now().isoformat() + "Z", # Current time in ISO format
                    "eventName": "ObjectCreated:Put",
                    "userIdentity": {"principalId": "AWS:AIDAWG234234234"},
                    "requestParameters": {"sourceIPAddress": "127.0.0.1"},
                    "responseElements": {
                        "x-amz-request-id": "REQUESTID",
                        "x-amz-id-2": "HOSTID"
                    },
                    "s3": {
                        "s3SchemaVersion": "1.0",
                        "configurationId": "testConfig",
                        "bucket": {
                            "name": MOCKED_S3_BUCKET_NAME,
                            "ownerIdentity": {"principalId": "A3NL1O00000000"},
                            "arn": f"arn:aws:s3:::{MOCKED_S3_BUCKET_NAME}"
                        },
                        "object": {
                            "key": test_file_key,
                            "size": len(test_file_content.encode('utf-8')),
                            "eTag": "mocked-etag",
                            "sequencer": "0A1B2C3D4E5F678901"
                        }
                    }
                }
            ]
        }
        mock_lambda_context = {} # Lambda context object can be empty for this test

        print("Invoking Lambda handler directly with mocked S3 event...")
        from handler import lambda_handler
        lambda_handler(mock_s3_event, mock_lambda_context)
        print("Lambda handler invocation complete.")

        # 5. Verify the metadata in DynamoDB
        print(f"Attempting to retrieve item with object_key '{test_file_key}' from mocked DynamoDB...")
        response = dynamodb_client.get_item(
            TableName=MOCKED_DYNAMODB_TABLE_NAME,
            Key={
                'object_key': {'S': test_file_key}
            }
        )

        item = response.get('Item')

        # Pytest assertions
        assert item is not None, f"Item with object_key '{test_file_key}' not found in mocked DynamoDB."

        print("Item found in mocked DynamoDB:")
        # Print the item in a readable format
        for key, value in item.items():
            if isinstance(value, dict) and len(value) == 1:
                type_key = list(value.keys())[0]
                print(f"  {key}: {value[type_key]}")
            else:
                print(f"  {key}: {value}")

        # Assertions
        assert item['bucket_name']['S'] == MOCKED_S3_BUCKET_NAME, "Bucket name mismatch"
        assert item['object_key']['S'] == test_file_key, "Object key mismatch"
        assert int(item['size_bytes']['N']) == len(test_file_content.encode('utf-8')), "File size mismatch"
        assert 'last_modified' in item, "Last modified timestamp missing"
        assert 'etag' in item, "ETag missing"
        assert 'content_type' in item, "Content type missing"
        assert 'event_time' in item, "Event time missing"
        assert 'user_metadata' in item, "User metadata missing"
        # Verify custom user metadata
        assert json.loads(item['user_metadata']['S']) == {'test_metadata': 'mocked_value'}, "User metadata mismatch"

        print("\nIntegration Test Passed: Metadata successfully found and verified in mocked DynamoDB.")

    except Exception as e:
        # In Pytest, an unhandled exception will cause the test to fail.
        # We re-raise the exception after printing for better debugging in CI logs.
        print(f"Integration Test Failed due to an error: {e}")
        raise # Re-raise the exception to make pytest fail the test
    finally:
        # Clean up environment variables set for the test
        if 'DYNAMODB_TABLE_NAME' in os.environ:
            del os.environ['DYNAMODB_TABLE_NAME']
        print("Cleaned up environment variables.")

