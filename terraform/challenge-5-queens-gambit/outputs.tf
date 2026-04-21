output "scout_access_key_id" {
  description = "Access Key ID for the scout user (provide to students)"
  value       = aws_iam_access_key.scout.id
}

output "scout_secret_access_key" {
  description = "Secret Access Key for the scout user (provide to students)"
  value       = nonsensitive(aws_iam_access_key.scout.secret)
}

output "bucket_name" {
  description = "S3 bucket name (for admin reference only)"
  value       = aws_s3_bucket.mission_briefing.id
}

output "flag_secret_arn" {
  description = "ARN of the flag secret (for admin reference only)"
  value       = aws_secretsmanager_secret.flag.arn
}
