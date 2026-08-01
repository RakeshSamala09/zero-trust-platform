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

  tags = {
    Name = "${var.project_name}-ec2-node-role"
  }
}

# Pull permission for ECR (Jenkins builds push here, nodes pull from here)
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

########################################
# CI user (github-actions-ecr-push) — SCOPED, not FullAccess.
#
# Previously this user had AmazonEC2FullAccess + AmazonS3FullAccess
# attached, which contradicts the zero-trust design of this stack: a
# leaked static key for this user would mean full EC2 + full S3 control
# on the whole account. Replaced with a single least-privilege inline
# policy scoped to exactly what CI needs:
#   - push/pull images to ECR
#   - create/manage the EC2 instances this stack provisions
#   - read/write the Terraform state object + use the lock table
#
# Longer term: replace this static-key user entirely with GitHub OIDC
# (see PART 4 below) and delete this user.
########################################

data "aws_caller_identity" "current" {}

resource "aws_iam_user_policy" "github_actions_scoped" {
  name = "${var.project_name}-github-actions-scoped"
  user = "github-actions-ecr-push"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Lifecycle"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:Describe*",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-tf-state-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::${var.project_name}-tf-state-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Sid    = "TerraformLockTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-tf-lock"
      }
    ]
  })
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

# EBS CSI driver permissions — needed so nodes can dynamically create,
# attach, and manage EBS volumes for PersistentVolumeClaims. Attached to
# the node role (not a pod-identity role) since the self-hosted OIDC
# provider's kube-apiserver wiring (--service-account-issuer) hasn't been
# completed yet — this is the pragmatic, known-working path for now.
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ec2_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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

########################################
# PART 4 (optional, recommended next step): GitHub OIDC role
#
# Uncomment + fill in <ACCOUNT_ID>/<GITHUB_ORG>/<GITHUB_REPO> to let
# GitHub Actions assume a role via OIDC instead of using the static
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY secrets in the workflow.
# Once this works, delete the github-actions-ecr-push IAM user entirely.
########################################

# resource "aws_iam_openid_connect_provider" "github" {
#   url             = "https://token.actions.githubusercontent.com"
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
# }
#
# resource "aws_iam_role" "github_actions" {
#   name = "${var.project_name}-github-actions-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = {
#         Federated = aws_iam_openid_connect_provider.github.arn
#       }
#       Action = "sts:AssumeRoleWithWebIdentity"
#       Condition = {
#         StringEquals = {
#           "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#         }
#         StringLike = {
#           "token.actions.githubusercontent.com:sub" = "repo:<GITHUB_ORG>/<GITHUB_REPO>:ref:refs/heads/main"
#         }
#       }
#     }]
#   })
# }
