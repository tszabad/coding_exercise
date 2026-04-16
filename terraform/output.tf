output "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  value       = data.aws_s3_bucket.landing_bucket.id
}

output "preprocessed_bucket_name" {
  description = "Name of the preprocessed output S3 bucket"
  value       = aws_s3_bucket.curated_zone_bucket.bucket
}

output "lambda_function_name" {
  description = "Name of the preprocessing Lambda function"
  value       = aws_lambda_function.preprocessing.function_name
}

output "lambda_function_arn" {
  description = "ARN of the preprocessing Lambda function"
  value       = aws_lambda_function.preprocessing.arn
}