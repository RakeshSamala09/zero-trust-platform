terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Optional: uncomment to keep state remotely (recommended once you're
  # comfortable — for now, local state is fine for a weekend project)
  # backend "s3" {
  #   bucket = "your-tf-state-bucket"
  #   key    = "zero-trust-platform/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region
}