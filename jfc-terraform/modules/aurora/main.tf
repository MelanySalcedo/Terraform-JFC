# Aurora Module - RDS Aurora Provisioned MySQL

# DB Subnet Group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = {
    Name        = "${var.project_name}-aurora-subnet-group"
    Environment = var.environment
  }
}

# DB Parameter Group
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project_name}-aurora-cluster-params"
  family      = "aurora-mysql8.0"
  description = "Aurora cluster parameter group for ${var.project_name}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  tags = {
    Name        = "${var.project_name}-aurora-cluster-params"
    Environment = var.environment
  }
}

resource "aws_db_parameter_group" "aurora" {
  name        = "${var.project_name}-aurora-instance-params"
  family      = "aurora-mysql8.0"
  description = "Aurora instance parameter group for ${var.project_name}"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = {
    Name        = "${var.project_name}-aurora-instance-params"
    Environment = var.environment
  }
}

# Aurora Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.project_name}-aurora-cluster"
  engine                          = "aurora-mysql"
  engine_version                  = "8.0.mysql_aurora.3.04.0"
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = var.master_password
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [var.security_group_id]
  
  backup_retention_period      = 7
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
  
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  
  storage_encrypted = true
  kms_key_id        = var.kms_key_id
  
  # Backups y snapshots
  skip_final_snapshot       = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "dev" ? null : "${var.project_name}-aurora-final-snapshot"
  
  # Backtrack: permite "retroceder" la base de datos en el tiempo (hasta 72 horas)
  # Útil para recuperarse rápidamente de errores sin restaurar desde backup
  backtrack_window = var.environment == "prod" ? 72 : 0
  
  apply_immediately = var.environment == "dev" ? true : false
  
  lifecycle {
    # Ignora cambios en el nombre del snapshot final para evitar drift en Terraform
    ignore_changes = [final_snapshot_identifier]
  }

  tags = {
    Name        = "${var.project_name}-aurora-cluster"
    Environment = var.environment
  }
}

# Aurora Writer Instance
resource "aws_rds_cluster_instance" "writer" {
  identifier              = "${var.project_name}-aurora-writer"
  cluster_identifier      = aws_rds_cluster.aurora.id
  instance_class          = var.instance_class
  engine                  = aws_rds_cluster.aurora.engine
  engine_version          = aws_rds_cluster.aurora.engine_version
  db_parameter_group_name = aws_db_parameter_group.aurora.name
  
  publicly_accessible = false
  
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_id
  performance_insights_retention_period = 7
  
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "${var.project_name}-aurora-writer"
    Environment = var.environment
    Role        = "writer"
  }
}

# Aurora Reader Instance
resource "aws_rds_cluster_instance" "reader" {
  identifier              = "${var.project_name}-aurora-reader"
  cluster_identifier      = aws_rds_cluster.aurora.id
  instance_class          = var.instance_class
  engine                  = aws_rds_cluster.aurora.engine
  engine_version          = aws_rds_cluster.aurora.engine_version
  db_parameter_group_name = aws_db_parameter_group.aurora.name
  
  publicly_accessible = false
  
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_id
  performance_insights_retention_period = 7
  
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "${var.project_name}-aurora-reader"
    Environment = var.environment
    Role        = "reader"
  }
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-rds-monitoring-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
