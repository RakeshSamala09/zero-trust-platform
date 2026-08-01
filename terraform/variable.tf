variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used on all resource names/tags"
  type        = string
  default     = "zero-trust-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet (keeps cost down — no NAT gateway needed)"
  type        = string
  default     = "10.20.1.0/24"
}

variable "availability_zone" {
  description = "AZ for the subnet and instances"
  type        = string
  default     = "ap-south-1a"
}

variable "my_ip_cidr" {from https://checkip.amazonaws.com. Used to lock down SSH and K8s API to only you."
  description = "YOUR public IP in CIDR form, e.g. 1.2.3.4/32 — get it 
  type        = string
  # no default on purpose — force yourself to set this, don't leave SSH open to 0.0.0.0/0
}

variable "instance_type" {
  description = "EC2 instance type for all 5 nodes"
  type        = string
  default     = "m7i-flex.large"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access (create one in AWS console/CLI first)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Optional: path to a local public key file if you want Terraform to create the key pair instead of using an existing one. Leave empty to use an existing key_pair_name."
  type        = string
  default     = ""
}
