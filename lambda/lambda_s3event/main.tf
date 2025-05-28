provider "aws" {
  region = "ap-south-1"

}

resource "aws_s3_bucket" "s3_lambda_bucket" {
  bucket = "nevil-s3-lambda-bucket"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }]
    }
  )

}

resource "aws_iam_role_policy_attachment" "lambda_log" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

}

resource "aws_lambda_function" "s3_trigger_lambda" {
  function_name    = "S3_Event_trigger"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")


}

resource "aws_lambda_permission" "allowS3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.s3_lambda_bucket.arn

}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.s3_lambda_bucket.id
  lambda_function {

    lambda_function_arn = aws_lambda_function.s3_trigger_lambda.arn
    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*"
    ]
  }
  depends_on = [aws_lambda_permission.allowS3]
}

resource "aws_sqs_queue" "success_s3" {
  name = "success_s3"
}

resource "aws_sqs_queue" "failure_s3" {
  name = "failure_s3"

}

resource "aws_lambda_function_event_invoke_config" "lambda_destination" {
  function_name = aws_lambda_function.s3_trigger_lambda.function_name
  destination_config {
    on_success {
      destination = aws_sqs_queue.success_s3.arn
    }
    on_failure {
      destination = aws_sqs_queue.failure_s3.arn
    }

  }
  maximum_retry_attempts = 0
  qualifier              = "$LATEST"

}
resource "aws_iam_role_policy" "lambda_destination_policy" {
  name = "lambda-destination-policy"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sqs:SendMessage"
        Resource = [aws_sqs_queue.success_s3.arn,
        aws_sqs_queue.failure_s3.arn]
      }
    ]
  })

}


