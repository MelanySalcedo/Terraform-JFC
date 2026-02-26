# JFC E-Commerce - Terraform Infrastructure

Infraestructura como código para la aplicación de e-commerce de JFC en AWS.

## Arquitectura

Esta infraestructura implementa una arquitectura serverless Multi-AZ con los siguientes componentes:

- **Compute:** ECS Fargate con auto-scaling (2-10 tareas)
- **Database:** Aurora Provisioned MySQL (Multi-AZ)
- **Cache:** ElastiCache Redis (Multi-AZ con failover automático)
- **Load Balancer:** Application Load Balancer (ALB)
- **Storage:** S3 (imágenes) + EFS (archivos compartidos)
- **Networking:** VPC con subnets públicas y privadas en 2 AZs
- **Security:** Security Groups, IAM Roles, Secrets Manager, KMS
- **Container Registry:** ECR con escaneo de vulnerabilidades

## Estructura del Proyecto

```
jfc-terraform/
├── modules/                    # Módulos reutilizables
│   ├── vpc/                   # VPC, subnets, NAT, VPC endpoints
│   ├── security/              # Security groups, IAM, Secrets Manager
│   ├── aurora/                # RDS Aurora Provisioned
│   ├── redis/                 # ElastiCache Redis
│   ├── alb/                   # Application Load Balancer
│   ├── ecs/                   # ECS Fargate con auto-scaling
│   ├── cloudfront/            # CloudFront distribution
│   └── monitoring/            # CloudWatch alarms y dashboards
├── environments/
│   ├── dev/                   # Configuración de desarrollo
│   └── prod/                  # Configuración de producción
└── README.md
```

## Requisitos Previos

1. **Terraform:** >= 1.5.0
2. **AWS CLI:** Configurado con credenciales válidas
3. **Certificado ACM:** Crear certificado SSL/TLS en AWS Certificate Manager
4. **S3 Backend:** Crear bucket para Terraform state

### Crear S3 Backend

```bash
# Crear bucket para Terraform state
aws s3api create-bucket \
  --bucket jfc-terraform-state-prod \
  --region us-east-1

# Habilitar versionado
aws s3api put-bucket-versioning \
  --bucket jfc-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Habilitar cifrado
aws s3api put-bucket-encryption \
  --bucket jfc-terraform-state-prod \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Crear tabla DynamoDB para locks
aws dynamodb create-table \
  --table-name jfc-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Crear Certificado ACM

```bash
# Solicitar certificado (reemplaza con tu dominio)
aws acm request-certificate \
  --domain-name jfc-ecommerce.com \
  --subject-alternative-names "*.jfc-ecommerce.com" \
  --validation-method DNS \
  --region us-east-1

# Validar el certificado siguiendo las instrucciones en la consola de AWS
# Guarda el ARN del certificado para usarlo en terraform.tfvars
```

## Despliegue

### 1. Configurar Variables

```bash
cd environments/prod
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tus valores:

```hcl
project_name = "jfc"
aws_region   = "us-east-1"

container_image = "123456789.dkr.ecr.us-east-1.amazonaws.com/jfc-app:latest"
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789:certificate/xxx"

db_username = "admin"
db_password = "TuPasswordSeguro123!"
redis_auth_token = "TuTokenSeguro456!"
```

### 2. Inicializar Terraform

```bash
terraform init
```

### 3. Planificar Cambios

```bash
terraform plan
```

### 4. Aplicar Infraestructura

```bash
terraform apply
```

**Tiempo estimado:** 15-20 minutos

### 5. Obtener Outputs

```bash
terraform output
```

Outputs importantes:
- `alb_dns_name`: DNS del ALB para configurar Route 53
- `ecr_repository_url`: URL del repositorio ECR para push de imágenes
- `ecs_cluster_name`: Nombre del cluster ECS

## Configuración Post-Despliegue

### 1. Configurar Route 53

```bash
# Crear registro CNAME apuntando a ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.jfc-ecommerce.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'"$(terraform output -raw alb_dns_name)"'"}]
      }
    }]
  }'
```

### 2. Push de Imagen Docker a ECR

```bash
# Login a ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url)

# Build imagen
docker build -t jfc-app:latest .

# Tag imagen
docker tag jfc-app:latest $(terraform output -raw ecr_repository_url):latest

# Push imagen
docker push $(terraform output -raw ecr_repository_url):latest
```

### 3. Actualizar ECS Service

```bash
# Forzar nuevo despliegue con imagen actualizada
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service jfc-app-service \
  --force-new-deployment \
  --region us-east-1
```

## Acceso a Contenedores (ECS Exec)

```bash
# Listar tareas en ejecución
aws ecs list-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service-name jfc-app-service \
  --region us-east-1

# Conectar a un contenedor
aws ecs execute-command \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task <TASK_ID> \
  --container jfc-app \
  --interactive \
  --command "/bin/bash"
```

## Monitoreo

### CloudWatch Logs

```bash
# Ver logs de ECS
aws logs tail /ecs/jfc --follow --region us-east-1
```

### Métricas de Auto-Scaling

El auto-scaling está configurado con 3 políticas:

1. **CPU:** Target 70% (scale out en 60s, scale in en 300s)
2. **Memory:** Target 80% (scale out en 60s, scale in en 300s)
3. **ALB Requests:** Target 1000 req/target (scale out en 60s, scale in en 300s)

## Costos Estimados (Producción)

| Servicio | Configuración | Costo Mensual |
|----------|--------------|---------------|
| ECS Fargate | 4 tareas promedio (0.5 vCPU, 1GB) | ~$71-89 |
| Aurora Provisioned | db.r6g.medium Writer + Reader + Backtrack | ~$230 |
| ElastiCache Redis | cache.r6g.medium Primary + Replica | ~$155 |
| ALB | 1 ALB + data transfer + logs | ~$27-37 |
| S3 + CloudFront | 100GB storage + 1TB transfer | ~$50-85 |
| EFS | 50GB Standard | ~$15 |
| NAT Gateway | 2 NAT (Multi-AZ) | ~$65 |
| CloudWatch | Alarms + logs | ~$3 |
| **Total** | | **~$616-679/mes** |

**Costos en Dev:** ~$300-350/mes (menos tareas, sin backtrack)

## Seguridad

- Cifrado en tránsito (TLS 1.3)
- Cifrado en reposo (KMS)
- Secrets Manager para credenciales
- Security Groups con mínimo privilegio
- IAM Roles con políticas específicas
- VPC Endpoints para servicios AWS
- Private subnets para app y datos
- ALB Access Logs para auditoría
- CloudWatch Alarms para monitoreo proactivo

## Características Destacadas

### Optimización de Costos
- **NAT optimizado:** 1 NAT en dev, 2 en prod
- **Lifecycle policies:** Eliminación automática de logs antiguos
- **Auto-scaling:** Escala según demanda real

### Alta Disponibilidad
- **Multi-AZ:** Todos los componentes críticos
- **Auto-scaling:** 2-10 tareas según demanda
- **Failover automático:** Aurora y Redis
- **Circuit breaker:** ECS con rollback automático

### Resiliencia
- **Aurora Backtrack:** Rollback en segundos (hasta 72 horas)
- **Health checks:** Configurados para apps Node.js
- **Reserved memory:** Redis estable sin crashes

### Observabilidad
- **CloudWatch Alarms:** 6 alarmas críticas
- **ALB Access Logs:** Auditoría completa de tráfico
- **Container Insights:** Métricas detalladas de ECS
- **Performance Insights:** Métricas de Aurora

## Mantenimiento

### Actualizar Infraestructura

```bash
# Planificar cambios
terraform plan

# Aplicar cambios
terraform apply
```

### Backup y Recuperación

- **Aurora:** Backups automáticos (7 días de retención)
- **Redis:** Snapshots automáticos (5 días de retención)
- **Terraform State:** Versionado en S3

### Destruir Infraestructura

```bash
# CUIDADO: Esto eliminará TODA la infraestructura
terraform destroy
```

## Troubleshooting

### ECS Tasks no inician

```bash
# Ver eventos del servicio
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services jfc-app-service \
  --region us-east-1 \
  --query 'services[0].events[0:5]'

# Ver logs de la tarea
aws logs tail /ecs/jfc --follow --region us-east-1
```

### Health Checks fallan

```bash
# Verificar target group health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1
```

### Problemas de conectividad

```bash
# Verificar security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=JFC-Ecommerce" \
  --region us-east-1
```


