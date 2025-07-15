import os
import json
import boto3
import time
import uuid

logs_client = boto3.client("logs")

LOG_GROUP = os.environ["LOG_GROUP"]
LOG_STREAM = f"stream-{int(time.time())}-{uuid.uuid4()}"

def lambda_handler(event, context):
    try:
        # Create log stream (once per invocation)s
        logs_client.create_log_stream(
            logGroupName=LOG_GROUP,
            logStreamName=LOG_STREAM
        )

        log_events = []

        for record in event.get("Records", []):
            sns_message = record.get("Sns", {}).get("Message", "{}")

            # Parse the SES event JSON inside the SNS message
            try:
                ses_event = json.loads(sns_message)
            except json.JSONDecodeError:
                ses_event = {"raw": sns_message}  # Fallback to raw string

            log_events.append({
                "timestamp": int(time.time() * 1000),
                "message": json.dumps(ses_event)
            })

        # Send logs
        logs_client.put_log_events(
            logGroupName=LOG_GROUP,
            logStreamName=LOG_STREAM,
            logEvents=log_events
        )

        return {"status": "ok", "events_logged": len(log_events)}

    except Exception as e:
        print(f"Error processing SES event: {str(e)}")
        raise
