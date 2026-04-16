variable "aws_region" {
  description = "AWS region to deploy resources into"
  default     = "eu-north-1"
}

variable "pandas_layer_arn" {
  description = "ARN of the AWS SDK Pandas Lambda layer"
  type        = string
  default     = "arn:aws:lambda:eu-north-1:336392948345:layer:AWSSDKPandas-Python312:22"
}


variable "bucket_curated_zone" {
  type        = string
  description = "Name of the S3 bucket for curated zone"
  default     = "snapsoft-homework-curated-zone-tsz"
}

