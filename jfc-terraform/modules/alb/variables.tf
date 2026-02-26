variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "target_port" {
  description = "Target port for the application"
  type        = number
  default     = 3000
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

# ELB Service Account ID por región (para ALB logs)
# us-east-1: 127311923021
# Referencia: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
variable "elb_account_id" {
  description = "ELB service account ID for the region"
  type        = string
  default     = "127311923021"  # us-east-1
}
