output "website_url" {
  description = "S3 static website URL for the challenge"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "bucket_name" {
  description = "S3 bucket name (needed for aws s3 ls)"
  value       = aws_s3_bucket.website.id
}

output "reader_access_key_id" {
  description = "Access key ID for hivectf-ch1-reader (embedded in .bak file)"
  value       = aws_iam_access_key.reader.id
}

output "reader_secret_access_key" {
  description = "Secret access key for hivectf-ch1-reader (embedded in .bak file)"
  value       = nonsensitive(aws_iam_access_key.reader.secret)
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing the flag"
  value       = aws_secretsmanager_secret.flag.arn
}
