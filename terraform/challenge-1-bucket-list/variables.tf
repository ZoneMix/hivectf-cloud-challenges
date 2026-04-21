variable "aws_profile" {
  description = "AWS CLI profile to use for deployment (Account 1)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "challenge_flag" {
  description = "The CTF flag value stored in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "HiveCTF"
    Challenge   = "1-bucket-list"
    Environment = "ctf"
    ManagedBy   = "terraform"
  }
}
