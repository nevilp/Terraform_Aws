provider "aws" {
  region = "ap-south-1"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "null_resource" "build_lambda" {
  triggers = {
    code_hash = sha1(file("lambda/handler.py"))
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      if [ -d lambda/lambda.zip ]; then
        rm -rf lambda/lambda.zip
      elif [ -f lambda/lambda.zip ]; then
        rm -f lambda/lambda.zip
      fi

      mkdir -p lambda/build
      cp lambda/handler.py lambda/build/
      cd lambda/build && zip -r ../lambda.zip .
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}


resource "aws_lambda_function" "my_lambda" {
  function_name = "myLambdaTerraform"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "${path.module}/lambda/lambda.zip"
  depends_on    = [null_resource.build_lambda]
}
