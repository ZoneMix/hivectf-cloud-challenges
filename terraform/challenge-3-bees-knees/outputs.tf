output "api_base_url" {
  description = "Base API Gateway URL (give to students - they must discover endpoints)"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "bucket_name" {
  description = "S3 bucket containing sensor data and flag"
  value       = aws_s3_bucket.sensor_data.id
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.sensor_api.function_name
}
