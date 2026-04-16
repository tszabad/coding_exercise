# Configure AWS provider

terraform {
  backend "s3" {
    bucket = "snapsoft-homework-tf-state-tsz"
    key    = "terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = var.aws_region
}