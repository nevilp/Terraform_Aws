provider "aws" {
    region = "ap-south-1"
  
}

resource "aws_sqs_queue" "sqs_lambda" {
    name = "sqs-lambda-eventsourcing"
  
}

resource "aws_iam_role" "lambda_exec_role" {
    name = "lambda_exec_role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow"
                Action = "sts:AssumeRole"
                Principal = {
          Service = "lambda.amazonaws.com"
        }

            }
        ]
    }
    )
  
}

resource "aws_iam_role_policy_attachment" "lambda_log" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

}

resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  
}

resource "aws_lambda_function" "lambda_sqs_function" {
    function_name = "lambda_sqs_function"
    role = aws_iam_role.lambda_exec_role.arn
    handler = "lambda_function.lambda_handler"
    filename = "lambda_function.zip"
    runtime = "python3.10"
    source_code_hash = filebase64sha256("lambda_function.zip")
  
}

resource "aws_lambda_event_source_mapping" "lambda_sqs_trigger" {
  function_name = aws_lambda_function.lambda_sqs_function.function_name
  event_source_arn = aws_sqs_queue.sqs_lambda.arn
  batch_size = 10
  enabled = true
}