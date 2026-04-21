########################################
# Challenge 3 - Bee's Knees
# SSTI/Command Injection via Lambda
# Attack: API injection -> cred leak -> S3 flag
########################################

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

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

data "aws_caller_identity" "current" {}

# ----------------------------------------------------------------------
# Random suffix for globally unique bucket name
# ----------------------------------------------------------------------
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# ----------------------------------------------------------------------
# S3 Bucket - Sensor data storage (contains the flag)
# ----------------------------------------------------------------------
resource "aws_s3_bucket" "sensor_data" {
  bucket        = "hivectf-hive-sensor-data-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = {
    Challenge = "3-bees-knees"
    Project   = "HiveCTF"
  }
}

resource "aws_s3_bucket_public_access_block" "sensor_data" {
  bucket = aws_s3_bucket.sensor_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- S3 Objects: Sensor JSON files ---

resource "aws_s3_object" "sensor_hv001" {
  bucket       = aws_s3_bucket.sensor_data.id
  key          = "sensors/HV-001.json"
  content_type = "application/json"
  content = jsonencode({
    sensor_id   = "HV-001"
    location    = "Hive Alpha"
    coordinates = { lat = 43.8791, lon = -97.0100 }
    installed   = "2025-06-15"
    firmware    = "v2.3.1"
    readings = [
      { timestamp = "2026-04-04T08:30:00Z", temperature = 35.2, humidity = 62, bee_count = 48200 },
      { timestamp = "2026-04-04T08:00:00Z", temperature = 34.9, humidity = 63, bee_count = 47800 },
      { timestamp = "2026-04-04T07:30:00Z", temperature = 34.5, humidity = 64, bee_count = 47100 },
    ]
  })
}

resource "aws_s3_object" "sensor_hv002" {
  bucket       = aws_s3_bucket.sensor_data.id
  key          = "sensors/HV-002.json"
  content_type = "application/json"
  content = jsonencode({
    sensor_id   = "HV-002"
    location    = "Hive Beta"
    coordinates = { lat = 43.8805, lon = -97.0085 }
    installed   = "2025-07-22"
    firmware    = "v2.3.1"
    readings = [
      { timestamp = "2026-04-04T08:31:00Z", temperature = 34.8, humidity = 58, bee_count = 51400 },
      { timestamp = "2026-04-04T08:01:00Z", temperature = 34.6, humidity = 59, bee_count = 51100 },
      { timestamp = "2026-04-04T07:31:00Z", temperature = 34.2, humidity = 60, bee_count = 50800 },
    ]
  })
}

resource "aws_s3_object" "sensor_hv003" {
  bucket       = aws_s3_bucket.sensor_data.id
  key          = "sensors/HV-003.json"
  content_type = "application/json"
  content = jsonencode({
    sensor_id   = "HV-003"
    location    = "Hive Gamma"
    coordinates = { lat = 43.8778, lon = -97.0120 }
    installed   = "2025-09-10"
    firmware    = "v2.2.0"
    readings = [
      { timestamp = "2026-04-03T22:15:00Z", temperature = 31.1, humidity = 71, bee_count = 12300 },
      { timestamp = "2026-04-03T21:45:00Z", temperature = 30.8, humidity = 72, bee_count = 12100 },
      { timestamp = "2026-04-03T21:15:00Z", temperature = 30.5, humidity = 73, bee_count = 11900 },
    ]
    maintenance_note = "Colony health below threshold. Inspection scheduled 2026-04-07."
  })
}

resource "aws_s3_object" "monthly_report" {
  bucket       = aws_s3_bucket.sensor_data.id
  key          = "reports/monthly-2026-03.json"
  content_type = "application/json"
  content = jsonencode({
    report_period = "2026-03"
    generated_at  = "2026-04-01T00:00:00Z"
    summary = {
      total_sensors    = 3
      active_sensors   = 2
      avg_temperature  = 34.1
      avg_humidity     = 63.7
      total_bee_count  = 111900
      alerts_triggered = 4
    }
    notes = "Hive Gamma showing declining population. Recommend on-site inspection."
  })
}

resource "aws_s3_object" "flag" {
  bucket       = aws_s3_bucket.sensor_data.id
  key          = "classified/flag.txt"
  content_type = "text/plain"
  content      = var.flag
}

# ----------------------------------------------------------------------
# IAM Role for Lambda execution
# ----------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# KMS key for Lambda environment variable encryption
resource "aws_kms_key" "lambda_env" {
  description             = "HiveCTF Ch3 - Lambda env var encryption"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowLambdaRoleDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.challenge_name}-sensor-api-role"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.challenge_name}-sensor-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Challenge = "3-bees-knees"
    Project   = "HiveCTF"
  }
}

# CloudWatch Logs permissions
data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logging" {
  name   = "${var.challenge_name}-lambda-logging"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_logging.json
}

# KMS decrypt for Lambda environment variable encryption
resource "aws_iam_role_policy" "lambda_kms" {
  name = "${var.challenge_name}-lambda-kms"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
      }
    ]
  })
}

# S3 read-only access to the sensor data bucket
data "aws_iam_policy_document" "lambda_s3_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.sensor_data.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sensor_data.arn}/*"]
  }
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name   = "${var.challenge_name}-lambda-s3-access"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_s3_access.json
}

# ----------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "sensor_api" {
  function_name    = "${var.challenge_name}-sensor-api"
  description      = "HiveWatch Sensor API - retrieves sensor data by ID"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  kms_key_arn = aws_kms_key.lambda_env.arn

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.sensor_data.id
    }
  }

  tags = {
    Challenge = "3-bees-knees"
    Project   = "HiveCTF"
  }
}

resource "aws_cloudwatch_log_group" "sensor_api" {
  name              = "/aws/lambda/${aws_lambda_function.sensor_api.function_name}"
  retention_in_days = 7

  tags = {
    Challenge = "3-bees-knees"
    Project   = "HiveCTF"
  }
}

# ----------------------------------------------------------------------
# API Gateway (REST API)
# ----------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "sensor_api" {
  name        = "${var.challenge_name}-hivewatch-api"
  description = "HiveWatch Sensor Monitoring API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Challenge = "3-bees-knees"
    Project   = "HiveCTF"
  }
}

# /sensor resource
resource "aws_api_gateway_resource" "sensor" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  parent_id   = aws_api_gateway_rest_api.sensor_api.root_resource_id
  path_part   = "sensor"
}

# GET /sensor
resource "aws_api_gateway_method" "get_sensor" {
  rest_api_id   = aws_api_gateway_rest_api.sensor_api.id
  resource_id   = aws_api_gateway_resource.sensor.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.id" = false
  }
}

# Lambda integration
resource "aws_api_gateway_integration" "lambda_sensor" {
  rest_api_id             = aws_api_gateway_rest_api.sensor_api.id
  resource_id             = aws_api_gateway_resource.sensor.id
  http_method             = aws_api_gateway_method.get_sensor.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sensor_api.invoke_arn
}

# ----------------------------------------------------------------------
# Decoy endpoints (for endpoint discovery via fuzzing)
# ----------------------------------------------------------------------

# /health - decoy health check
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  parent_id   = aws_api_gateway_rest_api.sensor_api.root_resource_id
  path_part   = "health"
}

resource "aws_api_gateway_method" "get_health" {
  rest_api_id   = aws_api_gateway_rest_api.sensor_api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health_mock" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.get_health.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "health_200" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.get_health.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "health_200" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.get_health.http_method
  status_code = aws_api_gateway_method_response.health_200.status_code

  response_templates = {
    "application/json" = jsonencode({
      status  = "ok"
      service = "hivewatch-api"
      version = "1.4.2"
    })
  }
}

# /status - decoy status endpoint
resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  parent_id   = aws_api_gateway_rest_api.sensor_api.root_resource_id
  path_part   = "status"
}

resource "aws_api_gateway_method" "get_status" {
  rest_api_id   = aws_api_gateway_rest_api.sensor_api.id
  resource_id   = aws_api_gateway_resource.status.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "status_mock" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.get_status.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "status_200" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.get_status.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "status_200" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.get_status.http_method
  status_code = aws_api_gateway_method_response.status_200.status_code

  response_templates = {
    "application/json" = jsonencode({
      sensors_online  = 3
      sensors_offline = 0
      last_update     = "2026-04-04T08:31:00Z"
      region          = "Great Plains - Sector 7"
      uptime_pct      = 99.7
    })
  }
}

# /info - decoy info endpoint
resource "aws_api_gateway_resource" "info" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  parent_id   = aws_api_gateway_rest_api.sensor_api.root_resource_id
  path_part   = "info"
}

resource "aws_api_gateway_method" "get_info" {
  rest_api_id   = aws_api_gateway_rest_api.sensor_api.id
  resource_id   = aws_api_gateway_resource.info.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "info_mock" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.info.id
  http_method = aws_api_gateway_method.get_info.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "info_200" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.info.id
  http_method = aws_api_gateway_method.get_info.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "info_200" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  resource_id = aws_api_gateway_resource.info.id
  http_method = aws_api_gateway_method.get_info.http_method
  status_code = aws_api_gateway_method_response.info_200.status_code

  response_templates = {
    "application/json" = jsonencode({
      api_name    = "HiveWatch Sensor Monitoring Platform"
      operator    = "HiveWatch Industries LLC"
      contact     = "api-support@hivewatch.io"
      docs        = "Internal use only - contact api-support for access"
      tos_version = "2025-11"
    })
  }
}

# Deploy the API
resource "aws_api_gateway_deployment" "sensor_api" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.sensor.id,
      aws_api_gateway_method.get_sensor.id,
      aws_api_gateway_integration.lambda_sensor.id,
      aws_api_gateway_resource.health.id,
      aws_api_gateway_integration.health_mock.id,
      aws_api_gateway_integration_response.health_200.id,
      aws_api_gateway_resource.status.id,
      aws_api_gateway_integration.status_mock.id,
      aws_api_gateway_integration_response.status_200.id,
      aws_api_gateway_resource.info.id,
      aws_api_gateway_integration.info_mock.id,
      aws_api_gateway_integration_response.info_200.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda_sensor,
    aws_api_gateway_integration_response.health_200,
    aws_api_gateway_integration_response.status_200,
    aws_api_gateway_integration_response.info_200,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.sensor_api.id
  rest_api_id   = aws_api_gateway_rest_api.sensor_api.id
  stage_name    = "prod"

  tags = {
    Challenge = "3-bees-knees"
    Project   = "HiveCTF"
  }
}

# Throttling settings
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.sensor_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

# Lambda permission for API Gateway invocation
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sensor_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.sensor_api.execution_arn}/*/*"
}
