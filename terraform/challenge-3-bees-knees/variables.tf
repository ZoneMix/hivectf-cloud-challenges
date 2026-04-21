variable "aws_profile" {
  description = "AWS CLI profile to use for deployment (Account 1)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "challenge_name" {
  description = "Name prefix for challenge resources"
  type        = string
  default     = "hivectf-ch3"
}

variable "flag" {
  description = "CTF flag value"
  type        = string
  sensitive   = true
}
