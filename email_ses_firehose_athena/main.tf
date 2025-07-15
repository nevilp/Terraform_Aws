provider "aws" {
    region = "ap-south-1"
}

resource "aws_s3_bucket" "ses_log_bucket" {
    bucket = "ses-failure-logs-${random_id.suffix.hex}"
    force_destroy = true
}

resource "random_id" "suffix"{
    byte_length = 4
}

resource "aws_sns_topic" "ses_event_topic"{
    name = "ses-event-topic"
}

resource "aws_cloudwatch_log_group" "ses_logs" {
    name = "/aws/ses/failures"
    retention_in_days = 90

  
}

resource "aws_iam_role" "lambda_exec_role"{
    name = "lambda_ses_event_role"
    assume_role_policy = jsonencode({
        Version= "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Principal = {Service : "lambda.amazonaws.com"}
            Effect = "Allow"
        }]
    })
}

resource "aws_iam_policy_attachment" "lambda_log" {
    name = "lambda-basic-logs"
    roles = [aws_iam_role.lambda_exec_role.name]
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  
}

resource "aws_iam_role_policy" "lambda_cw_write" {
    name = "lambda-cloudwatch-logs"
    role = aws_iam_role.lambda_exec_role.id
    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [{
            Action = "logs:PutLogEvents"
            Effect = "Allow",
            Resource = "${aws_cloudwatch_log_group.ses_logs.arn}:*"
        }]
    }

    )
  
}

data "archive_file" "lambda_zip" {
    type = "zip"
    source_dir = "${path.module}/lambda"
    output_path = "${path.module}/lambda.zip"

}

resource "aws_lambda_function" "log_ses" {
    function_name = "log_ses_events"
    role = aws_iam_role.lambda_exec_role.arn
    handler = "handler.lambda_handler"
    runtime = "python3.12"
    filename = data.archive_file.lambda_zip.output_path
    timeout = 10
    environment {
      variables = {
        LOG_GROUP = aws_cloudwatch_log_group.ses_logs.name
      }
    }
  
}

resource "aws_lambda_permission" "allow_sns" {
    statement_id = "AllowExecutionFromSNS"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.log_ses.function_name
    principal = "sns.amazonaws.com"
    source_arn = aws_sns_topic.ses_event_topic.arn
  
}

resource "aws_sns_topic_subscription" "lambda_sub" {
    topic_arn = aws_sns_topic.ses_event_topic.arn
    protocol = "lambda"
    endpoint = aws_lambda_function.log_ses.arn  
}


resource "aws_ses_configuration_set" "ses_config" {
    name = "ses-config-hybrid"
}

resource "aws_ses_event_destination" "ses_event_dest" {
    name = "ses-hybrid-dest"
    configuration_set_name = aws_ses_configuration_set.ses_config.name
    enabled = true
    matching_types = ["bounce","complaint"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_event_topic.arn
    }

    
}



