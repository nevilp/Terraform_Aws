def lambda_handler(event, context):
    for record in event['Records']:
        if record['eventName'] == 'REMOVE':
            expired = record['dynamodb'].get('OldImage', {})
            user_id = expired.get('UserId', {}).get('S')
            print(f"TTL Expired Record Detected: {user_id}")