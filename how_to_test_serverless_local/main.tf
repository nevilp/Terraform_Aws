# Configure the AWS provider
provider "aws" {
  region = "ap-south-1" # Mumbai region
}

# --- S3 Bucket for Uploads ---
resource "aws_s3_bucket" "upload_bucket" {
  bucket = "nevil-terraform-bucket-1234" # Replace with a globally unique bucket name
  tags = {
    Name        = "S3UploadBucket"
    Environment = "Dev"
  }
}



# --- DynamoDB Table for Metadata ---
resource "aws_dynamodb_table" "metadata_table" {
  name         = "S3ObjectMetadata"
  billing_mode = "PAY_PER_REQUEST" # On-demand capacity

  hash_key = "object_key" # Primary key for the table

  attribute {
    name = "object_key"
    type = "S" # String type
  }

  tags = {
    Name        = "S3ObjectMetadataTable"
    Environment = "Dev"
  }
}

# --- IAM Role for Lambda Execution ---
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_s3_dynamodb_exec_role"
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

# Attach basic Lambda execution role (for CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy to allow Lambda to read from S3 and write to DynamoDB
resource "aws_iam_policy" "lambda_s3_dynamodb_policy" {
  name        = "lambda_s3_dynamodb_policy"
  description = "Allows Lambda to read S3 object metadata and write to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectAttributes",
          "s3:HeadObject"
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.upload_bucket.arn}/*" # Allow access to objects in the specific bucket
      },
      {
        Action = [
          "dynamodb:PutItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.metadata_table.arn # Allow writing to the specific DynamoDB table
      }
    ]
  })
}

# Attach the custom policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_s3_dynamodb_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_s3_dynamodb_policy.arn
}

# --- Lambda Function Packaging ---
# This null_resource builds the Lambda deployment package (zip file)
resource "null_resource" "build_lambda" {
  triggers = {
    # Re-run this resource if handler.py changes
    code_hash = sha1(file("${path.module}/lambda/handler.py"))
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      # Clean up previous zip if it exists
      if [ -f ${path.module}/lambda/lambda.zip ]; then
        rm -f ${path.module}/lambda/lambda.zip
      fi

      # Create a build directory, copy handler.py, and zip it
      mkdir -p ${path.module}/lambda/build
      cp ${path.module}/lambda/handler.py ${path.module}/lambda/build/
      cd ${path.module}/lambda/build && zip -r ../lambda.zip .
    EOT
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module # Ensure commands run from the root of the module
  }
}

# --- AWS Lambda Function ---
resource "aws_lambda_function" "s3_metadata_processor" {
  function_name = "S3MetadataProcessorLambda"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "${path.module}/lambda/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/lambda.zip") # Recalculate hash on file change
  timeout       = 30 # Set a reasonable timeout
  memory_size   = 128 # Set a reasonable memory size

  depends_on    = [
    null_resource.build_lambda, # Ensure lambda zip is built before deploying
    aws_iam_role_policy_attachment.lambda_s3_dynamodb_policy_attach # Ensure policies are attached
  ]

  # Pass DynamoDB table name as an environment variable to the Lambda function
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.metadata_table.name
    }
  }
}

# --- S3 Bucket Notification to Trigger Lambda ---
resource "aws_s3_bucket_notification" "s3_bucket_notification" {
  bucket = aws_s3_bucket.upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_metadata_processor.arn
    events              = ["s3:ObjectCreated:*"] # Trigger on any object creation event
    # filter_prefix       = "uploads/" # Optional: Only trigger for objects in a specific folder
    # filter_suffix       = ".jpg"     # Optional: Only trigger for specific file types
  }

  # Ensure the Lambda function is created before setting up the notification
  depends_on = [aws_lambda_function.s3_metadata_processor]
}

# --- Lambda Permission for S3 to Invoke It ---
resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_metadata_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload_bucket.arn # Restrict invocation to this specific S3 bucket
}

# --- Outputs (Optional) ---
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.upload_bucket.bucket
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.metadata_table.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.s3_metadata_processor.function_name
}