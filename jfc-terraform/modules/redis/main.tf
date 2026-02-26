# ElastiCache Redis Module - Multi-AZ with Automatic Failover

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = {
    Name        = "${var.project_name}-redis-subnet-group"
    Environment = var.environment
  }
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.project_name}-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  # Reserva 25% de memoria para operaciones internas de Redis
  # Esto previene que Redis use 100% de RAM y crashee
  parameter {
    name  = "reserved-memory-percent"
    value = "25"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = {
    Name        = "${var.project_name}-redis-params"
    Environment = var.environment
  }
}

# ElastiCache Replication Group (Multi-AZ)
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Redis cluster for ${var.project_name}"
  
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.node_type
  num_cache_clusters   = 2  # 1 primary + 1 replica
  port                 = 6379
  
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.security_group_id]
  
  # Multi-AZ with automatic failover
  automatic_failover_enabled = true
  multi_az_enabled           = true
  
  # Auth token for security
  auth_token                 = var.auth_token
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_id
  
  # Backup configuration
  # Nota: Configurado para NO solaparse con Aurora (Aurora: 03:00-04:00)
  snapshot_retention_limit = 5
  snapshot_window          = "05:00-06:00"
  maintenance_window       = "tue:06:00-tue:08:00"  # Día diferente a Aurora
  
  # Notifications
  notification_topic_arn = var.sns_topic_arn
  
  # Auto minor version upgrade
  auto_minor_version_upgrade = true
  
  apply_immediately = var.environment == "dev" ? true : false

  tags = {
    Name        = "${var.project_name}-redis"
    Environment = var.environment
  }
}
