########################################
# PART 1: EC2 instance IAM role
# Zero trust principle: nodes get scoped AWS permissions via
# instance profile — never static access keys baked into the box.
########################################


resource "aws_iam_role" "ec2_node_role" {
  name = "${var.project_name}-ec2-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}








# Pull permission for ECR (Jenkins builds push here, nodes pull from here)
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM so you can shell in without opening SSH broadly later if you want
# (optional zero-trust upgrade path: swap SSH entirely for SSM Session Manager)
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent permissions (optional — useful if you forward system logs
# to CloudWatch in addition to ELK)
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_node_profile" {
  name = "${var.project_name}-ec2-node-profile"
  role = aws_iam_role.ec2_node_role.name
}

########################################
# PART 2: Self-hosted OIDC provider for Pod Identity
#
# On EKS this is automatic (IRSA). On self-managed kubeadm, you build the
# same mechanism yourself: an S3 bucket serves the OIDC discovery document
# and JWKS, kube-apiserver is configured to sign service account tokens
# against it, and IAM roles trust that OIDC provider.
#
# Terraform creates the bucket + provider registration here. The actual
# discovery.json / keys.json content gets generated and uploaded during
# your kubeadm bootstrap (Day 2) — see README "Pod Identity Setup" section
# for the exact commands, since the signing key must be generated on the
# master node itself.
########################################

resource "aws_s3_bucket" "oidc_provider" {
  bucket = "${var.project_name}-oidc-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-oidc-provider"
  }
}

resource "aws_s3_bucket_public_access_block" "oidc_provider" {
  bucket = aws_s3_bucket.oidc_provider.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "oidc_provider_public_read" {
  bucket = aws_s3_bucket.oidc_provider.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadForOIDCDiscovery"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.oidc_provider.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.oidc_provider]
}

resource "aws_s3_bucket_website_configuration" "oidc_provider" {
  bucket = aws_s3_bucket.oidc_provider.id

  index_document {
    suffix = "index.html"
  }
}

data "aws_caller_identity" "current" {}

# Fetches the TLS certificate thumbprint AWS needs to trust the S3-hosted
# OIDC issuer. S3 static website endpoints sit behind Amazon's own cert chain.
data "tls_certificate" "oidc_s3_cert" {
  url = "https://s3.${var.aws_region}.amazonaws.com"
}

resource "aws_iam_openid_connect_provider" "self_hosted" {
  # NOTE: url must exactly match the issuer you configure in kube-apiserver's
  # --service-account-issuer flag on Day 2. Using the bucket's REST endpoint
  # (not the website endpoint) since IAM OIDC providers require HTTPS.
  url = "https://${aws_s3_bucket.oidc_provider.bucket}.s3.${var.aws_region}.amazonaws.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [data.tls_certificate.oidc_s3_cert.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.project_name}-self-hosted-oidc"
  }
}

########################################
# PART 3: Example Pod Identity IAM role
#
# This is what a pod (e.g. Jenkins agent) assumes via its service account
# token instead of the node's role — true least-privilege, scoped to one
# workload instead of every pod on the node.
########################################

resource "aws_iam_role" "jenkins_pod_role" {
  name = "${var.project_name}-jenkins-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.self_hosted.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${aws_s3_bucket.oidc_provider.bucket}.s3.${var.aws_region}.amazonaws.com:sub" = "system:serviceaccount:jenkins:jenkins-agent"
          "${aws_s3_bucket.oidc_provider.bucket}.s3.${var.aws_region}.amazonaws.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-jenkins-pod-role"
  }
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_push" {
  role       = aws_iam_role.jenkins_pod_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}
