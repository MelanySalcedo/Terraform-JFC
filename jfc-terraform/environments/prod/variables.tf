variable "project_name" {
  description = "Project name"
  type        = string
  default     = "jfc"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "container_image" {
  description = "Docker image for the application"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

variable "cloudfront_aliases" {
  description = "CloudFront domain aliases (e.g., ['www.jfc.com', 'jfc.com'])"
  type        = list(string)
  default     = []
}

variable "db_username" {
  description = "Database master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Redis authentication token"
  type        = string
  sensitive   = true
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarms"
  type        = string
  default     = ""
}

# Route 53 (Opcional - descomentar si gestionas el dominio)
# variable "domain_name" {
#   description = "Domain name for Route 53 (e.g., jfc-ecommerce.com)"
#   type        = string
#   default     = ""
# }

