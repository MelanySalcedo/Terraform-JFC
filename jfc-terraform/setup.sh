#!/bin/bash
# JFC Terraform - Quick Setup Script

set -e

echo "🚀 JFC E-Commerce - Terraform Setup"
echo "===================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found. Please install Terraform >= 1.5.0${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Terraform found: $(terraform version | head -n1)${NC}"
echo -e "${GREEN}✅ AWS CLI found: $(aws --version)${NC}"
echo ""

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
echo -e "${GREEN}✅ AWS Account: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${GREEN}✅ AWS Region: ${AWS_REGION}${NC}"
echo ""

# Select environment
echo "🌍 Select environment:"
echo "1) Production"
echo "2) Development"
read -p "Enter choice [1-2]: " env_choice

case $env_choice in
    1)
        ENV="prod"
        ;;
    2)
        ENV="dev"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}✅ Environment: ${ENV}${NC}"
echo ""

# Create S3 backend
echo "📦 Setting up S3 backend for Terraform state..."
BUCKET_NAME="jfc-terraform-state-${ENV}"

if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating S3 bucket: ${BUCKET_NAME}"
    aws s3api create-bucket --bucket ${BUCKET_NAME} --region ${AWS_REGION}
    
    echo "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    echo "Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    echo -e "${GREEN}✅ S3 bucket created${NC}"
else
    echo -e "${YELLOW}⚠️  S3 bucket already exists${NC}"
fi
echo ""

# Create DynamoDB table for locks
echo "🔒 Setting up DynamoDB table for state locking..."
TABLE_NAME="jfc-terraform-locks"

if ! aws dynamodb describe-table --table-name ${TABLE_NAME} &> /dev/null; then
    echo "Creating DynamoDB table: ${TABLE_NAME}"
    aws dynamodb create-table \
        --table-name ${TABLE_NAME} \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region ${AWS_REGION}
    
    echo "Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name ${TABLE_NAME}
    echo -e "${GREEN}✅ DynamoDB table created${NC}"
else
    echo -e "${YELLOW}⚠️  DynamoDB table already exists${NC}"
fi
echo ""

# Create ECR repository
echo "🐳 Setting up ECR repository..."
REPO_NAME="jfc-app"

if ! aws ecr describe-repositories --repository-names ${REPO_NAME} &> /dev/null; then
    echo "Creating ECR repository: ${REPO_NAME}"
    aws ecr create-repository \
        --repository-name ${REPO_NAME} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=KMS \
        --region ${AWS_REGION}
    
    echo -e "${GREEN}✅ ECR repository created${NC}"
else
    echo -e "${YELLOW}⚠️  ECR repository already exists${NC}"
fi

ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"
echo -e "${GREEN}ECR URL: ${ECR_URL}${NC}"
echo ""

# Check for ACM certificate
echo "🔐 Checking for ACM certificate..."
CERT_ARN=$(aws acm list-certificates --region ${AWS_REGION} --query 'CertificateSummaryList[0].CertificateArn' --output text 2>/dev/null || echo "")

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
    echo -e "${YELLOW}⚠️  No ACM certificate found${NC}"
    echo "You need to create an ACM certificate for HTTPS"
    echo "Run: aws acm request-certificate --domain-name your-domain.com --validation-method DNS"
    CERT_ARN="REPLACE_WITH_YOUR_ACM_CERTIFICATE_ARN"
else
    echo -e "${GREEN}✅ ACM certificate found: ${CERT_ARN}${NC}"
fi
echo ""

# Generate terraform.tfvars
echo "📝 Generating terraform.tfvars..."
cd "environments/${ENV}"

if [ ! -f terraform.tfvars ]; then
    cat > terraform.tfvars <<EOF
project_name = "jfc"
aws_region   = "${AWS_REGION}"

# Container image from ECR
container_image = "${ECR_URL}:latest"

# ACM Certificate ARN for HTTPS
acm_certificate_arn = "${CERT_ARN}"

# Database credentials (CHANGE THESE!)
db_username = "admin"
db_password = "$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)"

# Redis auth token (CHANGE THIS!)
redis_auth_token = "$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)"
EOF
    echo -e "${GREEN}✅ terraform.tfvars created${NC}"
    echo -e "${YELLOW}⚠️  IMPORTANT: Review and update terraform.tfvars with your values${NC}"
else
    echo -e "${YELLOW}⚠️  terraform.tfvars already exists, skipping${NC}"
fi
echo ""

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init
echo -e "${GREEN}✅ Terraform initialized${NC}"
echo ""

# Summary
echo "✨ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review and update: environments/${ENV}/terraform.tfvars"
echo "2. Plan infrastructure: terraform plan"
echo "3. Apply infrastructure: terraform apply"
echo ""
echo "📚 For more information, see README.md"
