def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'text/plain'
        },
        'body': 'Hello from Lambda! Updated',
        'isBase64Encoded': False
    }
