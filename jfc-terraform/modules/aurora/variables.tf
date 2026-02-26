variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "private_data_subnet_ids" {
  description = "List of private data subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for Aurora"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "database_name" {
  description = "Initial database name"
  type        = string
  default     = "jfc_ecommerce"
}

variable "master_username" {
  description = "Master username for Aurora"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password for Aurora"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
  default     = "db.t4g.medium"
}
