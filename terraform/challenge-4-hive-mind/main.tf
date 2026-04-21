# =============================================================================
# Challenge 4: Hive Mind - Cognito Credential Vending + DynamoDB Breadcrumbs
# =============================================================================

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# Lambda: Pre-Signup Auto-Confirm Trigger
# =============================================================================

data "archive_file" "auto_confirm_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/auto_confirm.py"
  output_path = "${path.module}/lambda/auto_confirm.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.challenge_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "auto_confirm" {
  function_name    = "${var.challenge_prefix}-auto-confirm"
  filename         = data.archive_file.auto_confirm_zip.output_path
  source_code_hash = data.archive_file.auto_confirm_zip.output_base64sha256
  handler          = "auto_confirm.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_permission" "cognito_invoke" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_confirm.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.research_portal.arn
}

# =============================================================================
# Cognito User Pool
# =============================================================================

resource "aws_cognito_user_pool" "research_portal" {
  name = "${var.challenge_prefix}-research-portal"

  # Use email as the username
  username_attributes        = ["email"]
  auto_verified_attributes   = ["email"]

  password_policy {
    minimum_length                   = 8
    require_lowercase                = false
    require_numbers                  = false
    require_symbols                  = false
    require_uppercase                = false
    temporary_password_validity_days = 7
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  lambda_config {
    pre_sign_up = aws_lambda_function.auto_confirm.arn
  }

  username_configuration {
    case_sensitive = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "web_client" {
  name         = "${var.challenge_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.research_portal.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  generate_secret = false

  # Token validity
  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 30 # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# =============================================================================
# Cognito Identity Pool
# =============================================================================

resource "aws_cognito_identity_pool" "identity_pool" {
  identity_pool_name               = "${var.challenge_prefix}-identity-pool"
  allow_unauthenticated_identities = false
  allow_classic_flow               = true

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web_client.id
    provider_name           = "cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.research_portal.id}"
    server_side_token_check = false
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.identity_pool.id

  roles = {
    "authenticated" = aws_iam_role.authenticated_role.arn
  }
}

# =============================================================================
# IAM: Authenticated Role (what players get after Cognito auth)
# =============================================================================

resource "aws_iam_role" "authenticated_role" {
  name = "${var.challenge_prefix}-authenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.identity_pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "authenticated_dynamodb" {
  name = "${var.challenge_prefix}-dynamodb-read"
  role = aws_iam_role.authenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ScanNonVaultTables"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:DescribeTable",
          "dynamodb:BatchGetItem",
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.challenge_prefix}-users",
          "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.challenge_prefix}-research-logs",
          "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.challenge_prefix}-admin-notes",
        ]
      },
      {
        Sid    = "VaultGetItemOnly"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:DescribeTable",
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.challenge_prefix}-vault"
      },
      {
        Effect   = "Allow"
        Action   = "dynamodb:ListTables"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.challenge_prefix}-authenticated-role"
      },
    ]
  })
}

# Permission boundary to prevent escalation
resource "aws_iam_role_policy" "authenticated_deny" {
  name = "${var.challenge_prefix}-deny-dangerous"
  role = aws_iam_role.authenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
          "iam:PassRole",
          "s3:*",
          "lambda:*",
          "cognito-idp:*",
          "cognito-identity:*",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DeleteTable",
          "dynamodb:CreateTable",
          "dynamodb:UpdateTable",
          "ec2:*",
          "cloudformation:*",
          "cloudwatch:*",
          "logs:*",
          "sns:*",
          "sqs:*",
          "kms:*",
          "secretsmanager:*",
          "ssm:*",
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# DynamoDB Tables
# =============================================================================

# --- Users Table ---
resource "aws_dynamodb_table" "users" {
  name         = "${var.challenge_prefix}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "user_1" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    user_id    = { S = "USR-001" }
    name       = { S = "Dr. Elena Vasquez" }
    email      = { S = "e.vasquez@hivemind.io" }
    role       = { S = "Senior Researcher" }
    department = { S = "Behavioral Analysis" }
    status     = { S = "active" }
    joined     = { S = "2024-03-15" }
  })
}

resource "aws_dynamodb_table_item" "user_2" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    user_id    = { S = "USR-002" }
    name       = { S = "Marcus Chen" }
    email      = { S = "m.chen@hivemind.io" }
    role       = { S = "Lab Technician" }
    department = { S = "Colony Dynamics" }
    status     = { S = "active" }
    joined     = { S = "2024-06-01" }
  })
}

resource "aws_dynamodb_table_item" "user_3" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    user_id    = { S = "USR-003" }
    name       = { S = "Dr. Aisha Patel" }
    email      = { S = "a.patel@hivemind.io" }
    role       = { S = "Research Director" }
    department = { S = "Neural Mapping" }
    status     = { S = "active" }
    joined     = { S = "2023-11-20" }
  })
}

resource "aws_dynamodb_table_item" "user_4" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    user_id    = { S = "USR-004" }
    name       = { S = "James Thornton" }
    email      = { S = "j.thornton@hivemind.io" }
    role       = { S = "Data Analyst" }
    department = { S = "Swarm Intelligence" }
    status     = { S = "inactive" }
    joined     = { S = "2024-01-10" }
    note       = { S = "Access revoked - contract ended" }
  })
}

resource "aws_dynamodb_table_item" "user_5" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    user_id    = { S = "USR-005" }
    name       = { S = "Dr. Yuki Tanaka" }
    email      = { S = "y.tanaka@hivemind.io" }
    role       = { S = "Entomologist" }
    department = { S = "Species Catalog" }
    status     = { S = "active" }
    joined     = { S = "2024-08-22" }
  })
}

# --- Research Logs Table ---
resource "aws_dynamodb_table" "research_logs" {
  name         = "${var.challenge_prefix}-research-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "log_id"

  attribute {
    name = "log_id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "log_1" {
  table_name = aws_dynamodb_table.research_logs.name
  hash_key   = aws_dynamodb_table.research_logs.hash_key

  item = jsonencode({
    log_id     = { S = "LOG-2025-0142" }
    date       = { S = "2025-09-14" }
    researcher = { S = "Dr. Elena Vasquez" }
    subject    = { S = "Colony behavioral shift observed in Sector 7" }
    summary    = { S = "Unusual waggle dance patterns detected among worker bees in the western apiary. Frequency increased 340% over baseline. Possible environmental stressor or new communication protocol." }
    status     = { S = "under_review" }
  })
}

resource "aws_dynamodb_table_item" "log_2" {
  table_name = aws_dynamodb_table.research_logs.name
  hash_key   = aws_dynamodb_table.research_logs.hash_key

  item = jsonencode({
    log_id     = { S = "LOG-2025-0143" }
    date       = { S = "2025-09-15" }
    researcher = { S = "Marcus Chen" }
    subject    = { S = "Pollen sample analysis - Batch 47B" }
    summary    = { S = "Standard pollen composition analysis. No anomalies detected. Samples stored in Lab Freezer C, Rack 12." }
    status     = { S = "completed" }
  })
}

resource "aws_dynamodb_table_item" "log_3" {
  table_name = aws_dynamodb_table.research_logs.name
  hash_key   = aws_dynamodb_table.research_logs.hash_key

  item = jsonencode({
    log_id     = { S = "LOG-2025-0144" }
    date       = { S = "2025-09-16" }
    researcher = { S = "Dr. Aisha Patel" }
    subject    = { S = "Neural pathway mapping - Queen specimen Q-19" }
    summary    = { S = "Completed neural mapping of queen specimen Q-19. Results suggest enhanced pheromone production pathways not present in worker specimens. Data uploaded to internal research drive." }
    status     = { S = "completed" }
  })
}

resource "aws_dynamodb_table_item" "log_4" {
  table_name = aws_dynamodb_table.research_logs.name
  hash_key   = aws_dynamodb_table.research_logs.hash_key

  item = jsonencode({
    log_id     = { S = "LOG-2025-0145" }
    date       = { S = "2025-09-17" }
    researcher = { S = "Dr. Yuki Tanaka" }
    subject    = { S = "New subspecies catalog entry - Apis mellifera hivensis" }
    summary    = { S = "Documented new subspecies variant found in controlled environment. Exhibits 15% larger thorax and distinct coloring patterns. Genetic sequencing pending." }
    status     = { S = "pending_approval" }
  })
}

resource "aws_dynamodb_table_item" "log_5" {
  table_name = aws_dynamodb_table.research_logs.name
  hash_key   = aws_dynamodb_table.research_logs.hash_key

  item = jsonencode({
    log_id     = { S = "LOG-2025-0146" }
    date       = { S = "2025-09-18" }
    researcher = { S = "Dr. Aisha Patel" }
    subject    = { S = "Project Honeycomb - Phase 2 authorization" }
    summary    = { S = "Phase 2 of Project Honeycomb approved by the board. All classified materials have been moved to the secure vault. Access restricted to senior staff. See admin notes for vault access procedures." }
    status     = { S = "classified" }
  })
}

# --- Admin Notes Table ---
resource "aws_dynamodb_table" "admin_notes" {
  name         = "${var.challenge_prefix}-admin-notes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "note_id"

  attribute {
    name = "note_id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "note_1" {
  table_name = aws_dynamodb_table.admin_notes.name
  hash_key   = aws_dynamodb_table.admin_notes.hash_key

  item = jsonencode({
    note_id = { S = "ADMIN-001" }
    date    = { S = "2025-08-01" }
    author  = { S = "sysadmin@hivemind.io" }
    subject = { S = "Quarterly server maintenance" }
    content = { S = "Scheduled downtime for database migration on Aug 15. All researchers should save their work. Estimated 4-hour window." }
  })
}

resource "aws_dynamodb_table_item" "note_2" {
  table_name = aws_dynamodb_table.admin_notes.name
  hash_key   = aws_dynamodb_table.admin_notes.hash_key

  item = jsonencode({
    note_id = { S = "ADMIN-002" }
    date    = { S = "2025-08-20" }
    author  = { S = "hr@hivemind.io" }
    subject = { S = "New researcher onboarding" }
    content = { S = "Reminder: all new researchers must complete biosafety training before accessing Lab Sectors 5-9. Contact HR for scheduling." }
  })
}

resource "aws_dynamodb_table_item" "note_3" {
  table_name = aws_dynamodb_table.admin_notes.name
  hash_key   = aws_dynamodb_table.admin_notes.hash_key

  item = jsonencode({
    note_id = { S = "ADMIN-003" }
    date    = { S = "2025-09-01" }
    author  = { S = "security@hivemind.io" }
    subject = { S = "Badge access policy update" }
    content = { S = "Effective immediately: all badge access to Sector 9 requires dual-authorization. See updated policy document SEC-POL-2025-09." }
  })
}

resource "aws_dynamodb_table_item" "note_classified" {
  table_name = aws_dynamodb_table.admin_notes.name
  hash_key   = aws_dynamodb_table.admin_notes.hash_key

  item = jsonencode({
    note_id        = { S = "CLASSIFIED-001" }
    date           = { S = "2025-09-10" }
    author         = { S = "dr.queen@hivemind.io" }
    subject        = { S = "Project Honeycomb - Vault Access" }
    classification = { S = "TOP SECRET" }
    content        = { S = "The primary research vault has been secured with restricted access. All Project Honeycomb findings are stored under a single vault entry. Only those with the vault key may retrieve the data." }
    vault_key      = { S = "QUEEN-BEE-ALPHA" }
    hint           = { S = "Use this key to query the vault table. The key is the partition key value." }
  })
}

resource "aws_dynamodb_table_item" "note_4" {
  table_name = aws_dynamodb_table.admin_notes.name
  hash_key   = aws_dynamodb_table.admin_notes.hash_key

  item = jsonencode({
    note_id = { S = "ADMIN-004" }
    date    = { S = "2025-09-12" }
    author  = { S = "facilities@hivemind.io" }
    subject = { S = "Lab equipment calibration" }
    content = { S = "Annual calibration of spectrometers in Labs 3 and 4 completed. Certificates filed with QA department." }
  })
}

# --- Vault Table ---
resource "aws_dynamodb_table" "vault" {
  name         = "${var.challenge_prefix}-vault"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "vault_key"

  attribute {
    name = "vault_key"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "vault_decoy_1" {
  table_name = aws_dynamodb_table.vault.name
  hash_key   = aws_dynamodb_table.vault.hash_key

  item = jsonencode({
    vault_key      = { S = "DRONE-METRICS-2025" }
    classification = { S = "INTERNAL" }
    project        = { S = "Drone Population Study" }
    content        = { S = "Drone population metrics for Q3 2025: 12,400 specimens tracked across 8 colonies. Mortality rate within expected parameters." }
  })
}

resource "aws_dynamodb_table_item" "vault_decoy_2" {
  table_name = aws_dynamodb_table.vault.name
  hash_key   = aws_dynamodb_table.vault.hash_key

  item = jsonencode({
    vault_key      = { S = "POLLEN-INDEX-Q3" }
    classification = { S = "INTERNAL" }
    project        = { S = "Pollen Quality Index" }
    content        = { S = "Seasonal pollen quality scores. No actionable findings. Full dataset available on shared research drive." }
  })
}

resource "aws_dynamodb_table_item" "vault_flag" {
  table_name = aws_dynamodb_table.vault.name
  hash_key   = aws_dynamodb_table.vault.hash_key

  item = jsonencode({
    vault_key      = { S = "QUEEN-BEE-ALPHA" }
    classification = { S = "EYES ONLY" }
    project        = { S = "Project Honeycomb" }
    flag           = { S = var.flag }
    note           = { S = "Congratulations. You have accessed the queen's private vault." }
  })
}

# =============================================================================
# S3: Static Website Hosting
# =============================================================================

resource "aws_s3_bucket" "website" {
  bucket        = "${var.challenge_prefix}-research-portal-${random_string.bucket_suffix.result}"
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
      }
    ]
  })
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  content_type = "text/html"

  content = templatefile("${path.module}/assets/index.html", {
    cognito_user_pool_id     = aws_cognito_user_pool.research_portal.id
    cognito_client_id        = aws_cognito_user_pool_client.web_client.id
    cognito_identity_pool_id = aws_cognito_identity_pool.identity_pool.id
    cognito_region           = var.aws_region
    pool_suffix              = split("_", aws_cognito_user_pool.research_portal.id)[1]
  })
}
