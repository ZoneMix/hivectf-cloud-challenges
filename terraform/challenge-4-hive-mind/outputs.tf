output "website_url" {
  description = "URL of the HiveMind Research Portal"
  value       = "http://${aws_s3_bucket.website.bucket}.s3-website-${var.aws_region}.amazonaws.com"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.research_portal.id
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.web_client.id
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = aws_cognito_identity_pool.identity_pool.id
}
