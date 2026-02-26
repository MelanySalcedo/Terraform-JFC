# JFC E-Commerce Infrastructure - Production Environment

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "jfc-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "jfc-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "JFC-Ecommerce"
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"
  
  project_name    = var.project_name
  environment     = "prod"
  aws_region      = var.aws_region
  vpc_cidr        = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  public_subnet_cidrs       = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24"]
  private_data_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24"]
}

# Security Module
module "security" {
  source = "../../modules/security"
  
  project_name   = var.project_name
  environment    = "prod"
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
  vpc_id         = module.vpc.vpc_id
  app_port       = 3000
  
  db_username      = var.db_username
  db_password      = var.db_password
  redis_auth_token = var.redis_auth_token
}

# Aurora Module
module "aurora" {
  source = "../../modules/aurora"
  
  project_name            = var.project_name
  environment             = "prod"
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  security_group_id       = module.security.aurora_sg_id
  kms_key_id              = module.security.kms_key_id
  
  database_name   = "jfc_ecommerce"
  master_username = var.db_username
  master_password = var.db_password
  instance_class  = "db.r6g.medium"
}

# Redis Module
module "redis" {
  source = "../../modules/redis"
  
  project_name            = var.project_name
  environment             = "prod"
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  security_group_id       = module.security.redis_sg_id
  kms_key_id              = module.security.kms_key_id
  auth_token              = var.redis_auth_token
  node_type               = "cache.r6g.medium"
}

# ALB Module
module "alb" {
  source = "../../modules/alb"
  
  project_name      = var.project_name
  environment       = "prod"
  aws_account_id    = data.aws_caller_identity.current.account_id
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security.alb_sg_id
  target_port       = 3000
  certificate_arn   = var.acm_certificate_arn
}

# WAF Module (Web Application Firewall)
module "waf" {
  source = "../../modules/waf"
  
  project_name = var.project_name
  environment  = "prod"
  alb_arn      = module.alb.alb_arn
}

# Route 53 (DNS) - Opcional
# Descomentar si se gestiona el dominio en AWS
# 
# resource "aws_route53_zone" "main" {
#   name = var.domain_name
#
#   tags = {
#     Name        = "${var.project_name}-hosted-zone"
#     Environment = "prod"
#   }
# }
#
# # Registro A para API (ALB)
# resource "aws_route53_record" "api" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "api.${var.domain_name}"
#   type    = "A"
#
#   alias {
#     name                   = module.alb.alb_dns_name
#     zone_id                = module.alb.alb_zone_id
#     evaluate_target_health = true
#   }
# }
#
# # Registro A para Frontend (CloudFront)
# resource "aws_route53_record" "www" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "www.${var.domain_name}"
#   type    = "A"
#
#   alias {
#     name                   = module.cloudfront.cloudfront_domain_name
#     zone_id                = module.cloudfront.cloudfront_hosted_zone_id
#     evaluate_target_health = false
#   }
# }
#
# # Registro A para dominio raíz (CloudFront)
# resource "aws_route53_record" "root" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = var.domain_name
#   type    = "A"
#
#   alias {
#     name                   = module.cloudfront.cloudfront_domain_name
#     zone_id                = module.cloudfront.cloudfront_hosted_zone_id
#     evaluate_target_health = false
#   }
# }

# CloudFront Module (Frontend estático)
module "cloudfront" {
  source = "../../modules/cloudfront"
  
  project_name        = var.project_name
  environment         = "prod"
  aws_account_id      = data.aws_caller_identity.current.account_id
  acm_certificate_arn = var.acm_certificate_arn
  domain_aliases      = var.cloudfront_aliases
  price_class         = "PriceClass_100"  # USA, Canada, Europe
}

# EFS for shared storage
resource "aws_efs_file_system" "shared" {
  creation_token = "${var.project_name}-efs"
  encrypted      = true
  kms_key_id     = module.security.kms_key_id
  
  
  tags = {
    Name        = "${var.project_name}-efs"
    Environment = "prod"
  }
}

# AWS Backup Vault para EFS
resource "aws_backup_vault" "efs" {
  name = "${var.project_name}-efs-backup-vault"

  tags = {
    Name        = "${var.project_name}-efs-backup-vault"
    Environment = "prod"
  }
}

# AWS Backup Plan para EFS
resource "aws_backup_plan" "efs" {
  name = "${var.project_name}-efs-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.efs.name
    schedule          = "cron(0 5 * * ? *)"  # 5 AM UTC diario

    lifecycle {
      delete_after = 30  # Retención 30 días
    }
  }

  tags = {
    Name        = "${var.project_name}-efs-backup-plan"
    Environment = "prod"
  }
}

# IAM Role para AWS Backup
resource "aws_iam_role" "backup" {
  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backup-role"
    Environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# AWS Backup Selection (qué respaldar)
resource "aws_backup_selection" "efs" {
  name         = "${var.project_name}-efs-backup-selection"
  plan_id      = aws_backup_plan.efs.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    aws_efs_file_system.shared.arn
  ]
}

resource "aws_efs_mount_target" "shared" {
  count           = length(module.vpc.private_app_subnet_ids)
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = module.vpc.private_app_subnet_ids[count.index]
  security_groups = [module.security.efs_sg_id]
}

resource "aws_efs_access_point" "app" {
  file_system_id = aws_efs_file_system.shared.id
  
  posix_user {
    gid = 1000
    uid = 1000
  }
  
  root_directory {
    path = "/app"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
  
  tags = {
    Name        = "${var.project_name}-app-access-point"
    Environment = "prod"
  }
}

# ECS Module
module "ecs" {
  source = "../../modules/ecs"
  
  project_name           = var.project_name
  environment            = "prod"
  aws_region             = var.aws_region
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  security_group_id      = module.security.ecs_tasks_sg_id
  execution_role_arn     = module.security.ecs_task_execution_role_arn
  task_role_arn          = module.security.ecs_task_role_arn
  
  container_image = var.container_image
  container_port  = 3000
  task_cpu        = "512"
  task_memory     = "1024"
  
  desired_count = 4
  min_capacity  = 2
  max_capacity  = 10
  
  target_group_arn        = module.alb.target_group_arn
  alb_listener_arn        = module.alb.https_listener_arn
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  
  db_endpoint    = module.aurora.cluster_endpoint
  db_port        = module.aurora.cluster_port
  db_name        = module.aurora.database_name
  db_secret_arn  = module.security.db_credentials_secret_arn
  
  redis_endpoint    = module.redis.primary_endpoint
  redis_port        = module.redis.port
  redis_secret_arn  = module.security.redis_auth_secret_arn
  
  efs_id              = aws_efs_file_system.shared.id
  efs_access_point_id = aws_efs_access_point.app.id
  
  depends_on = [aws_efs_mount_target.shared]
}

# Monitoring Module
module "monitoring" {
  source = "../../modules/monitoring"
  
  project_name = var.project_name
  environment  = "prod"
  alarm_email  = var.alarm_email
  
  cluster_name                = module.ecs.cluster_name
  service_name                = module.ecs.service_name
  aurora_cluster_id           = module.aurora.cluster_id
  redis_replication_group_id  = module.redis.replication_group_id
  alb_arn_suffix              = module.alb.alb_arn_suffix
  target_group_arn_suffix     = module.alb.target_group_arn_suffix
}

# S3 Bucket for product images
resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-product-images-prod"
  
  tags = {
    Name        = "${var.project_name}-product-images"
    Environment = "prod"
  }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.security.kms_key_id
    }
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECR Repository
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = module.security.kms_key_id
  }
  
  tags = {
    Name        = "${var.project_name}-app"
    Environment = "prod"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
