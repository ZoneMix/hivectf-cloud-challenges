variable "account1_profile" {
  description = "AWS CLI profile for Account 1"
  type        = string
}

variable "account2_profile" {
  description = "AWS CLI profile for Account 2"
  type        = string
}

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "account1_id" {
  description = "AWS Account 1 ID"
  type        = string
}

variable "account2_id" {
  description = "AWS Account 2 ID"
  type        = string
}

variable "flag" {
  description = "The CTF flag"
  type        = string
  sensitive   = true
}
