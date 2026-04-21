###############################################################################
# Challenge 2 - Role Call (200 pts, Easy-Medium)
# Attack path: intern creds -> enumerate roles -> assume dev-role -> list
# Lambda functions -> read env vars -> extract flag
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  flag       = var.challenge_flag
  prefix     = "hivectf-ch2"
}

###############################################################################
# IAM User: hivectf-ch2-intern
###############################################################################

resource "aws_iam_user" "intern" {
  name                 = "${local.prefix}-intern"
  force_destroy        = true
  permissions_boundary = aws_iam_policy.intern_boundary.arn

  tags = {
    Challenge = "2-role-call"
    Purpose   = "CTF participant entry point"
  }
}

resource "aws_iam_access_key" "intern" {
  user = aws_iam_user.intern.name
}

# ---- Intern inline policy: enumeration + assume dev role -----------------

resource "aws_iam_user_policy" "intern_policy" {
  name = "${local.prefix}-intern-policy"
  user = aws_iam_user.intern.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListRoles"
        Effect   = "Allow"
        Action   = "iam:ListRoles"
        Resource = "*"
      },
      {
        Sid      = "AllowGetRole"
        Effect   = "Allow"
        Action   = "iam:GetRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${local.prefix}-*"
      },
      {
        Sid      = "AllowAssumeDevRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.dev_role.arn
      },
      {
        Sid    = "AllowReadOwnPolicies"
        Effect = "Allow"
        Action = [
          "iam:ListUserPolicies",
          "iam:ListAttachedUserPolicies",
          "iam:GetUserPolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:user/${local.prefix}-intern"
      },
      {
        Sid      = "AllowGetCallerIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

# ---- Permission boundary: deny all write / modify / delete ---------------

resource "aws_iam_policy" "intern_boundary" {
  name        = "${local.prefix}-intern-boundary"
  description = "Permission boundary for CTF intern - read-only, no mutations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadOnlyActions"
        Effect = "Allow"
        Action = [
          "iam:List*",
          "iam:Get*",
          "sts:AssumeRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyAllMutations"
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
      }
    ]
  })
}

###############################################################################
# IAM Role: hivectf-ch2-dev-role (assumable by intern)
###############################################################################

resource "aws_iam_role" "dev_role" {
  name = "${local.prefix}-dev-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInternAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:user/${local.prefix}-intern"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Challenge   = "2-role-call"
    Purpose     = "CTF pivot role - Lambda read access"
    Description = "Development role for internal Lambda inspection"
  }
}

resource "aws_iam_role_policy" "dev_role_lambda_policy" {
  name = "${local.prefix}-dev-lambda-policy"
  role = aws_iam_role.dev_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaReadOps"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:GetFunctionConfiguration",
          "lambda:GetFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${local.prefix}-*"
      },
      {
        Sid      = "AllowLambdaList"
        Effect   = "Allow"
        Action   = "lambda:ListFunctions"
        Resource = "*"
      },
      {
        Sid    = "AllowReadOwnPolicies"
        Effect = "Allow"
        Action = [
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${local.prefix}-dev-role"
      }
    ]
  })
}

###############################################################################
# Lambda Execution Roles (minimal - CloudWatch Logs only)
###############################################################################

resource "aws_iam_role" "processor_exec_role" {
  name = "${local.prefix}-processor-exec-role"

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
    Challenge = "2-role-call"
  }
}

resource "aws_iam_role_policy_attachment" "processor_logs" {
  role       = aws_iam_role.processor_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "public_api_exec_role" {
  name = "${local.prefix}-public-api-exec-role"

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
    Challenge = "2-role-call"
  }
}

resource "aws_iam_role_policy_attachment" "public_api_logs" {
  role       = aws_iam_role.public_api_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
# Lambda Functions
###############################################################################

data "archive_file" "processor_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/processor.py"
  output_path = "${path.module}/lambda/processor.zip"
}

data "archive_file" "public_api_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/public_api.py"
  output_path = "${path.module}/lambda/public_api.zip"
}

resource "aws_lambda_function" "processor" {
  function_name    = "${local.prefix}-internal-processor"
  filename         = data.archive_file.processor_zip.output_path
  source_code_hash = data.archive_file.processor_zip.output_base64sha256
  handler          = "processor.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.processor_exec_role.arn
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      FLAG        = local.flag
      ENVIRONMENT = "internal"
      SERVICE     = "data-processor"
    }
  }

  tags = {
    Challenge = "2-role-call"
    Purpose   = "Internal data processing - DO NOT EXPOSE"
  }
}

resource "aws_lambda_function" "public_api" {
  function_name    = "${local.prefix}-public-api"
  filename         = data.archive_file.public_api_zip.output_path
  source_code_hash = data.archive_file.public_api_zip.output_base64sha256
  handler          = "public_api.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.public_api_exec_role.arn
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      STAGE       = "production"
      ENVIRONMENT = "public"
      SERVICE     = "api-gateway"
    }
  }

  tags = {
    Challenge = "2-role-call"
    Purpose   = "Public API endpoint"
  }
}
