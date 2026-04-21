terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# Random suffix for globally unique bucket name
# ------------------------------------------------------------------------------

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  bucket_name = "hivectf-cloudnine-gallery-${random_string.bucket_suffix.result}"
  account_id  = data.aws_caller_identity.current.account_id
}

# ------------------------------------------------------------------------------
# S3 Bucket - Static Website Hosting (intentionally public for CTF)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "website" {
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  # Public access block must be disabled before policy can be applied
  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      },
      {
        Sid       = "PublicListBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.website.arn
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Upload website assets
# ------------------------------------------------------------------------------

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/assets/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/assets/index.html")
}

resource "aws_s3_object" "style_css" {
  bucket       = aws_s3_bucket.website.id
  key          = "style.css"
  source       = "${path.module}/assets/style.css"
  content_type = "text/css"
  etag         = filemd5("${path.module}/assets/style.css")
}

resource "aws_s3_object" "config_bak" {
  bucket       = aws_s3_bucket.website.id
  key          = "backups/employee-portal-config.bak"
  content_type = "application/octet-stream"

  content = templatefile("${path.module}/assets/config.bak.tpl", {
    access_key = aws_iam_access_key.reader.id
    secret_key = aws_iam_access_key.reader.secret
  })
}

# ------------------------------------------------------------------------------
# Secrets Manager - Flag
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "flag" {
  name                    = "hivectf/challenge1/flag"
  description             = "HiveCTF Challenge 1 - Bucket List flag"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id = aws_secretsmanager_secret.flag.id

  secret_string = jsonencode({
    flag = var.challenge_flag
  })
}

# ------------------------------------------------------------------------------
# IAM User - hivectf-ch1-reader (scoped to GetSecretValue only)
# ------------------------------------------------------------------------------

resource "aws_iam_user" "reader" {
  name                 = "hivectf-ch1-reader"
  permissions_boundary = aws_iam_policy.reader_boundary.arn
  force_destroy        = true
}

resource "aws_iam_access_key" "reader" {
  user = aws_iam_user.reader.name
}

# Policy: only secretsmanager:GetSecretValue on the specific secret
resource "aws_iam_policy" "reader_secrets" {
  name        = "hivectf-ch1-reader-secrets"
  description = "Allow GetSecretValue on the challenge 1 flag secret only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadFlag"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.flag.arn
      },
      {
        Sid    = "ListSecrets"
        Effect = "Allow"
        Action = "secretsmanager:ListSecrets"
        Resource = "*"
      },
      {
        Sid    = "DiscoverOwnPermissions"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedUserPolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion"
        ]
        Resource = [
          "arn:aws:iam::${local.account_id}:user/hivectf-ch1-reader",
          "arn:aws:iam::${local.account_id}:policy/hivectf-ch1-*"
        ]
      },
      {
        Sid    = "GetCallerIdentity"
        Effect = "Allow"
        Action = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "reader_secrets" {
  user       = aws_iam_user.reader.name
  policy_arn = aws_iam_policy.reader_secrets.arn
}

# ------------------------------------------------------------------------------
# Permission Boundary - prevent privilege escalation
# ------------------------------------------------------------------------------

resource "aws_iam_policy" "reader_boundary" {
  name        = "hivectf-ch1-reader-boundary"
  description = "Permission boundary: blocks IAM, STS (except GetCallerIdentity), and dangerous services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSTSGetCallerIdentity"
        Effect = "Allow"
        Action = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid    = "AllowReadOwnPolicies"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedUserPolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyIAMWrite"
        Effect = "Deny"
        Action = [
          "iam:Create*",
          "iam:Delete*",
          "iam:Put*",
          "iam:Update*",
          "iam:Attach*",
          "iam:Detach*",
          "iam:Add*",
          "iam:Remove*",
          "iam:Set*",
          "iam:Change*",
          "iam:Upload*",
          "iam:Enable*",
          "iam:Disable*",
          "iam:Deactivate*",
          "iam:Tag*",
          "iam:Untag*",
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDangerousServices"
        Effect = "Deny"
        Action = [
          "sts:AssumeRole",
          "sts:AssumeRoleWithSAML",
          "sts:AssumeRoleWithWebIdentity",
          "sts:GetFederationToken",
          "sts:GetSessionToken",
          "organizations:*",
          "account:*",
          "ec2:*",
          "lambda:*",
          "s3:PutBucketPolicy",
          "s3:DeleteBucket",
          "s3:PutObject",
          "s3:DeleteObject",
          "cloudformation:*",
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "config:DeleteConfigRule",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      }
    ]
  })
}
