output "intern_access_key_id" {
  description = "Access Key ID for the hivectf-ch2-intern user"
  value       = aws_iam_access_key.intern.id
}

output "intern_secret_access_key" {
  description = "Secret Access Key for the hivectf-ch2-intern user"
  value       = nonsensitive(aws_iam_access_key.intern.secret)
}

output "intern_username" {
  description = "IAM username for the intern"
  value       = aws_iam_user.intern.name
}

output "dev_role_arn" {
  description = "ARN of the dev role (for verification only)"
  value       = aws_iam_role.dev_role.arn
}

output "processor_function_name" {
  description = "Name of the flag-bearing Lambda function (for verification only)"
  value       = aws_lambda_function.processor.function_name
}

output "public_api_function_name" {
  description = "Name of the decoy Lambda function (for verification only)"
  value       = aws_lambda_function.public_api.function_name
}
