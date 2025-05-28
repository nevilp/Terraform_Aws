provider "aws" {
  region = "ap-south-1"
}


resource "aws_sqs_queue" "lamda_dlq" {
  name = "lamda_dlq"
}

resource "aws_iam_role" "lamda_dlq_exec" {
  name = "lamda_dlq_exec"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole",
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }]
    }
  )
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lamda_dlq_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lamda_dlq_policy" {
  name = "LambdaDLQPolicy"
  role = aws_iam_role.lamda_dlq_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sqs:SendMessage"
        Effect   = "Allow"
        Resource = aws_sqs_queue.lamda_dlq.arn
      }
    ]
  })


}

resource "aws_lambda_function" "lambda_dlq_function" {
  function_name    = "myFailingLambda"
  role             = aws_iam_role.lamda_dlq_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  dead_letter_config {

    target_arn = aws_sqs_queue.lamda_dlq.arn
  }

}