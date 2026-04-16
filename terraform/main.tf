terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Reference the pre-existing landing bucket
data "aws_s3_bucket" "landing_bucket" {
  bucket = "tamas-s3-landing-bucket-772498065476-eu-north-1-an"
}


# Curated zone output bucket

resource "aws_s3_bucket" "curated_zone_bucket" {
  bucket = var.bucket_curated_zone

  tags = {
    Name = "preprocessed-bucket"
  }
}

resource "aws_s3_bucket_versioning" "curated_zone_bucket" {
  bucket = aws_s3_bucket.curated_zone_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "curated_zone_bucket" {
  bucket = aws_s3_bucket.curated_zone_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "curated_zone_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.curated_zone_bucket]

  bucket = aws_s3_bucket.curated_zone_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "curated_zone_bucket" {
  bucket = aws_s3_bucket.curated_zone_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "curated_zone_bucket" {
  bucket                  = aws_s3_bucket.curated_zone_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


##########################################
# Lambda deployment package

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../resources/lambda/preprocessing_input_data"
  output_path = "${path.module}/lambda_package.zip"
}

# IAM execution role

data "aws_iam_role" "lambda_exec" {
  name = "preprocessing_input_data-role-9mmvm4mx"
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = data.aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "preprocessing-lambda-s3-policy"
  role = data.aws_iam_role.lambda_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${data.aws_s3_bucket.landing_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.curated_zone_bucket.arn}/*"
      }
    ]
  })
}

# Lambda function 

resource "aws_lambda_function" "preprocessing" {
  function_name    = "car-data-preprocessing"
  role             = data.aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "car_data_preprocessing.lambda_handler"
  runtime          = "python3.14"
  timeout          = 60
  memory_size      = 256

  layers = [var.pandas_layer_arn]

  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.curated_zone_bucket.bucket
    }
  }

  tags = {
    Name = "car-data-preprocessing"
  }
}

# Allow S3 to invoke Lambda 

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.preprocessing.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.landing_bucket.arn
}

# S3 event notification → Lambda 

resource "aws_s3_bucket_notification" "landing_trigger" {
  bucket = data.aws_s3_bucket.landing_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.preprocessing.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
