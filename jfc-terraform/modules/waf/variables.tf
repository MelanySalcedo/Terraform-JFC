variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN to associate with WAF"
  type        = string
}
