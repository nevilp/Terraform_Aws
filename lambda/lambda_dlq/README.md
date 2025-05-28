
#this method invokes async function call failing lambda causing after 2 attempt it will go to Dead letter Q
aws lambda invoke \
  --function-name myFailingLambda \
  --invocation-type Event \
  --payload '{"test": "sync-event"}' \
  --cli-binary-format raw-in-base64-out \
  response.json