########################################
# Remote state + locking
#
# NOTE: values in a `backend` block CANNOT reference variables — Terraform
# reads this before your variables are resolved. Replace the placeholders
# below with the exact bucket/table names printed as outputs by
# bootstrap-backend.tf (terraform output state_bucket_name / lock_table_name).
########################################

terraform {
  backend "s3" {
    bucket         = "zero-trust-tf-state-449902674551"   # <-- replace <ACCOUNT_ID>
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "zero-trust-tf-lock"
    encrypt        = true
  }
}
