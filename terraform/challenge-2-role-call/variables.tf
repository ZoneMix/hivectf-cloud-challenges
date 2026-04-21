variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use for deployment (Account 1)"
  type        = string
}

variable "challenge_flag" {
  description = "The CTF flag for this challenge"
  type        = string
  sensitive   = true
}
