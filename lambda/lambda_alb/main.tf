provider "aws" {
  region = "ap-south-1"

}

resource "aws_s3_bucket" "example" {
  bucket = "nevil-terrform-bucket"

}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]

  })


}

resource "aws_iam_role_policy_attachment" "lambdaLog" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

}

resource "aws_lambda_function" "lamda_test" {
  function_name    = "TerraformLambdaFunction"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  filename         = "${path.module}/lambda_function.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_function.zip")
  environment {
    variables = { ENV = "production" }
  }

}

resource "aws_security_group" "terraform-alb_sg" {
  name        = "terroform-alb-sg"
  description = "Allow HTTP"
  vpc_id      = "vpc-00add1acd514acecc"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }

}
resource "aws_alb" "lambda_alb" {
  name                       = "lambda-alb"
  load_balancer_type         = "application"
  subnets                    = ["subnet-08eb773ab9ac592c3", "subnet-02082298ecf534f4a", "subnet-076ed2b434bdb07bb"]
  security_groups            = [aws_security_group.terraform-alb_sg.id]
  enable_deletion_protection = false

}

resource "aws_lb_target_group" "lambda_tg" {
  name        = "lambda-target-group"
  target_type = "lambda"
  vpc_id      = "vpc-00add1acd514acecc"

}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.lambda_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }
}


resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lamda_test.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg.arn

}
resource "aws_lb_target_group_attachment" "target_group_lambda_attachment" {
  target_group_arn = aws_lb_target_group.lambda_tg.arn
  target_id        = aws_lambda_function.lamda_test.arn
}

