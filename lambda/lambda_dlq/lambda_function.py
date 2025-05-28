import json
def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    
    # Simulate a failure
    raise Exception("Intentional failure for DLQ testing")
