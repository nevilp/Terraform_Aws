provider "aws" {
  region = "ap-south-1"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
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
    role = aws_iam_role.lambda_exec.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "apigateway_lambda" {
    role = aws_iam_role.lambda_exec.arn
    function_name = "apigateway_lambda"
    filename = "lambda_function.zip"
    handler = "lambda_function.lambda_handler"
    source_code_hash = filebase64sha256("lambda_function.zip")
    runtime = "python3.10"
}

resource "aws_api_gateway_rest_api" "lambda_api" {
  name = "LambdaApi"
  description = "Api gateway to invoke lambda"
}

resource "aws_api_gateway_resource" "hello_resource" {
  path_part = "apigateway_lambda"
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id = aws_api_gateway_rest_api.lambda_api.root_resource_id
  
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  authorization = "NONE"
  http_method = "GET"
  resource_id = aws_api_gateway_resource.hello_resource.id
  
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id = "AllowGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.apigateway_lambda.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/*/*"
}

resource "aws_api_gateway_integration" "apigateway_lambda_integration" {
  http_method = aws_api_gateway_method.get_method.http_method
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  type = "AWS_PROXY"
  integration_http_method = "POST"
  resource_id = aws_api_gateway_resource.hello_resource.id
  uri = aws_lambda_function.apigateway_lambda.invoke_arn
  
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [ aws_api_gateway_integration.apigateway_lambda_integration ]
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  stage_name = "prod"
}

output "invoke_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}/apigateway_lambda"
}