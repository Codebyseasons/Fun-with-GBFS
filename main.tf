# Terraform script to create AWS Aurora Database, Secrets Manager, and Lambda

provider "aws" {
  region = "us-east-1" # Change as per your requirements
}

# Create a PostgreSQL RDS database cluster
resource "aws_rds_cluster" "postgresql_cluster" {
  cluster_identifier      = "postgresql-cluster"
  engine                  = "aurora-postgresql"  # Use Aurora PostgreSQL engine instead of 'postgres' for RDS clusters
  master_username         = "sumanth"
  master_password         = "sumanthdata123"  # Store securely in Secrets Manager
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  skip_final_snapshot     = true
  engine_version          = "16.3"  # Adjust as per the latest version
  db_subnet_group_name    = aws_db_subnet_group.default_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.postgresql_sg.id]
}

resource "aws_rds_cluster_instance" "postgresql_instance" {
  count               = 1  # For high availability, you may increase the count to 2 or more
  identifier          = "postgresql-instance-${count.index}"
  cluster_identifier  = aws_rds_cluster.postgresql_cluster.id
  instance_class      = "db.r5.large"
  publicly_accessible = false
  engine              = "aurora-postgresql"  # Use the Aurora PostgreSQL engine
}

# Subnet Group for PostgreSQL
resource "aws_db_subnet_group" "default_subnet_group" {
  name       = "default-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

# Data Source for Default Subnets
data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Default VPC Data Source
data "aws_vpc" "default" {
  default = true
}

# Security Group for PostgreSQL
resource "aws_security_group" "postgresql_sg" {
  name        = "postgresql-security-group"
  description = "Allow access to PostgreSQL"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"] # Adjust based on your VPC configuration
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Secrets Manager to store database credentials
resource "aws_secretsmanager_secret" "postgresql_secret" {
  name        = "postgresql-db-credentials"
  description = "Credentials for the PostgreSQL database"
}

resource "aws_secretsmanager_secret_version" "postgresql_secret_version" {
  secret_id = aws_secretsmanager_secret.postgresql_secret.id
  secret_string = jsonencode({
    username = "sumanth",
    password = "sumanthdata123"
  })
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "ec2-rds-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_rds_policy" {
  name        = "ec2-rds-policy"
  description = "Policy for EC2 to access PostgreSQL and Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = aws_secretsmanager_secret.postgresql_secret.arn
      },
      {
        Effect   = "Allow",
        Action   = ["rds:*"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_rds_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_rds_policy.arn
}

# Output the RDS endpoint
output "db_instance_endpoint" {
  value = aws_rds_cluster.postgresql_cluster.endpoint
}
