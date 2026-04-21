###############################################################################
# Challenge 5 - Queen's Gambit
# Cross-account pivot: Account 1 -> Account 2 -> Account 2 role chain -> Account 1
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------

provider "aws" {
  alias   = "account1"
  profile = var.account1_profile
  region  = var.region
}

provider "aws" {
  alias   = "account2"
  profile = var.account2_profile
  region  = var.region
}

# ---------------------------------------------------------------------------
# Random suffix for globally unique bucket name
# ---------------------------------------------------------------------------

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# ---------------------------------------------------------------------------
# Locals - ARNs constructed explicitly to break chicken-and-egg cycles
# ---------------------------------------------------------------------------

locals {
  bucket_name = "hivectf-ch5-mission-briefing-${random_string.bucket_suffix.result}"

  # Explicit ARN construction avoids circular dependencies between accounts
  liaison_role_arn      = "arn:aws:iam::${var.account2_id}:role/hivectf-ch5-liaison"
  intel_reader_role_arn = "arn:aws:iam::${var.account2_id}:role/hivectf-ch5-intel-reader"
  scout_user_arn        = "arn:aws:iam::${var.account1_id}:user/hivectf-ch5-scout"
  queen_user_arn        = "arn:aws:iam::${var.account1_id}:user/hivectf-ch5-queen"
  flag_secret_name      = "hivectf/challenge5/flag"

  # Base64-encoded role ARN for the intel file
  encoded_liaison_arn = base64encode(local.liaison_role_arn)
}

###############################################################################
#                           ACCOUNT 1 RESOURCES
###############################################################################

# ---------------------------------------------------------------------------
# S3 Bucket - Mission Briefing
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "mission_briefing" {
  provider = aws.account1
  bucket   = local.bucket_name

  force_destroy = true

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_s3_bucket_public_access_block" "mission_briefing" {
  provider = aws.account1
  bucket   = aws_s3_bucket.mission_briefing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "mission_briefing" {
  provider = aws.account1
  bucket   = aws_s3_bucket.mission_briefing.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "briefing" {
  provider     = aws.account1
  bucket       = aws_s3_bucket.mission_briefing.id
  key          = "briefing.txt"
  source       = "${path.module}/assets/briefing.txt"
  content_type = "text/plain"
  etag         = filemd5("${path.module}/assets/briefing.txt")
}

resource "aws_s3_object" "cross_border_contact" {
  provider     = aws.account1
  bucket       = aws_s3_bucket.mission_briefing.id
  key          = "intel/cross-border-contact.txt"
  content      = local.encoded_liaison_arn
  content_type = "text/plain"
}

# ---------------------------------------------------------------------------
# IAM User - Scout (starting credentials for students)
# ---------------------------------------------------------------------------

resource "aws_iam_user" "scout" {
  provider            = aws.account1
  name                = "hivectf-ch5-scout"
  permissions_boundary = aws_iam_policy.scout_boundary.arn

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_iam_access_key" "scout" {
  provider = aws.account1
  user     = aws_iam_user.scout.name
}

resource "aws_iam_policy" "scout_boundary" {
  provider    = aws.account1
  name        = "hivectf-ch5-scout-boundary"
  description = "Permission boundary for the scout user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListAllBuckets"
        Effect = "Allow"
        Action = "s3:ListAllMyBuckets"
        Resource = "*"
      },
      {
        Sid    = "AllowS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::hivectf-ch5-mission-briefing-*",
          "arn:aws:s3:::hivectf-ch5-mission-briefing-*/*"
        ]
      },
      {
        Sid    = "AllowAssumeRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = local.liaison_role_arn
      },
      {
        Sid    = "AllowGetCallerIdentity"
        Effect = "Allow"
        Action = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy" "scout" {
  provider = aws.account1
  name     = "hivectf-ch5-scout-policy"
  user     = aws_iam_user.scout.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAllBuckets"
        Effect = "Allow"
        Action = "s3:ListAllMyBuckets"
        Resource = "*"
      },
      {
        Sid    = "ListMissionBriefingBucket"
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.mission_briefing.arn
      },
      {
        Sid    = "GetMissionBriefingObjects"
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.mission_briefing.arn}/*"
      },
      {
        Sid    = "AssumeLiaisonRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = local.liaison_role_arn
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

# ---------------------------------------------------------------------------
# IAM User - Queen (final credentials stored in SSM, retrieves flag)
# ---------------------------------------------------------------------------

resource "aws_iam_user" "queen" {
  provider            = aws.account1
  name                = "hivectf-ch5-queen"
  permissions_boundary = aws_iam_policy.queen_boundary.arn

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_iam_access_key" "queen" {
  provider = aws.account1
  user     = aws_iam_user.queen.name
}

resource "aws_iam_policy" "queen_boundary" {
  provider    = aws.account1
  name        = "hivectf-ch5-queen-boundary"
  description = "Permission boundary for the queen user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGetFlag"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account1_id}:secret:${local.flag_secret_name}-*"
      },
      {
        Sid    = "AllowGetCallerIdentity"
        Effect = "Allow"
        Action = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy" "queen" {
  provider = aws.account1
  name     = "hivectf-ch5-queen-policy"
  user     = aws_iam_user.queen.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetFlagSecret"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account1_id}:secret:${local.flag_secret_name}-*"
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

# ---------------------------------------------------------------------------
# Secrets Manager - The Flag
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "flag" {
  provider                = aws.account1
  name                    = local.flag_secret_name
  description             = "HiveCTF Challenge 5 flag"
  recovery_window_in_days = 0

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_secretsmanager_secret_version" "flag" {
  provider      = aws.account1
  secret_id     = aws_secretsmanager_secret.flag.id
  secret_string = var.flag
}

###############################################################################
#                           ACCOUNT 2 RESOURCES
###############################################################################

# ---------------------------------------------------------------------------
# IAM Role - Liaison (cross-account entry point from Account 1)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "liaison" {
  provider = aws.account2
  name     = "hivectf-ch5-liaison"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccount1AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account1_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_iam_role_policy" "liaison" {
  provider = aws.account2
  name     = "hivectf-ch5-liaison-policy"
  role     = aws_iam_role.liaison.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListLambdaFunctions"
        Effect = "Allow"
        Action = "lambda:ListFunctions"
        Resource = "*"
      },
      {
        Sid    = "InvokeChallengeDecoder"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:${var.region}:${var.account2_id}:function:hivectf-ch5-*"
      },
      {
        Sid    = "EnumerateRoles"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "AssumeIntelReaderRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = local.intel_reader_role_arn
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

# ---------------------------------------------------------------------------
# IAM Role - Intel Reader (role chain: liaison -> intel-reader for SSM access)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "intel_reader" {
  provider = aws.account2
  name     = "hivectf-ch5-intel-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLiaisonAssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.liaison.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_iam_role_policy" "intel_reader" {
  provider = aws.account2
  name     = "hivectf-ch5-intel-reader-policy"
  role     = aws_iam_role.intel_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadQueenParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.region}:${var.account2_id}:parameter/hivectf/queen/*"
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

# ---------------------------------------------------------------------------
# Lambda - Decoder (passphrase gate, returns SSM paths)
# ---------------------------------------------------------------------------

data "archive_file" "decoder" {
  type        = "zip"
  source_file = "${path.module}/lambda/decoder.py"
  output_path = "${path.module}/lambda/decoder.zip"
}

resource "aws_iam_role" "decoder_execution" {
  provider = aws.account2
  name     = "hivectf-ch5-decoder-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_iam_role_policy" "decoder_execution" {
  provider = aws.account2
  name     = "hivectf-ch5-decoder-logging"
  role     = aws_iam_role.decoder_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${var.account2_id}:log-group:/aws/lambda/hivectf-ch5-decoder:*"
      }
    ]
  })
}

resource "aws_lambda_function" "decoder" {
  provider = aws.account2

  function_name = "hivectf-ch5-decoder"
  description   = "Queen's Gambit decoder - requires passphrase"
  role          = aws_iam_role.decoder_execution.arn

  filename         = data.archive_file.decoder.output_path
  source_code_hash = data.archive_file.decoder.output_base64sha256
  handler          = "decoder.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

# ---------------------------------------------------------------------------
# SSM Parameters - Queen's credentials (stored in Account 2)
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "queen_key_id" {
  provider = aws.account2
  name     = "/hivectf/queen/key-id"
  type     = "SecureString"
  value    = aws_iam_access_key.queen.id

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}

resource "aws_ssm_parameter" "queen_secret_key" {
  provider = aws.account2
  name     = "/hivectf/queen/secret-key"
  type     = "SecureString"
  value    = aws_iam_access_key.queen.secret

  tags = {
    Project   = "HiveCTF"
    Challenge = "5-queens-gambit"
  }
}
