variable "aws_profile" {
  description = "AWS CLI profile for deployment (Account 2)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS Account ID for Account 2"
  type        = string
}

variable "challenge_prefix" {
  description = "Prefix for all challenge resources"
  type        = string
  default     = "hivectf-ch4"
}

variable "flag" {
  description = "CTF flag for this challenge"
  type        = string
  sensitive   = true
}
