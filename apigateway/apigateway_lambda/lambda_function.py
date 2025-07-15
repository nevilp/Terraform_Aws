def lambda_handler(event,context):
     message ="Hello Lambda Api gateway based"
     response = {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": f'{{"message": "{message}"}}'
     }
     return response