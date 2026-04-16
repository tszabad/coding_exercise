variable "aws_region" {
  description = "AWS region to deploy resources into"
  default     = "eu-north-1"
}

variable "pandas_layer_arn" {
  description = "arn:aws:lambda:eu-north-1:336392948345:layer:AWSSDKPandas-Python314:2"
  type        = string
}




variable "bucket_curated_zone" {
  type        = string
  description = "Name of the S3 bucket for curated zone"
  default     = "snapsoft-homework-curated-zone-tsz"
}

