########################################
# BOOTSTRAP — run this ONCE, separately, with local state
# (i.e. in its own folder, no backend block here)
#
# terraform init
# terraform apply
#
# After this succeeds, note the bucket name + table name and put them
# into backend.tf (in your main terraform/ folder). Do NOT reuse this
# bootstrap folder for anything else, and do NOT delete this state file
# once the bucket/table exist for real usage.
########################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "project_name" {
  type    = string
  default = "zero-trust"
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project_name}-tf-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-tf-state"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project_name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-tf-lock"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}
