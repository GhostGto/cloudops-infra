terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

# Ubuntu AMI (most recent for focal/20.04)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Basic VPC
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "${var.project_name}-vpc" }
}

# Internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-igw" }
}

# Public subnets (2 AZs if available)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-a" }
}

resource "aws_subnet" "public_b" {
  count                   = length(data.aws_availability_zones.available.names) > 1 ? 1 : 0
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = length(data.aws_availability_zones.available.names) > 1 ? data.aws_availability_zones.available.names[1] : data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-b" }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "rta_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "rta_b" {
  count          = length(aws_subnet.public_b) > 0 ? 1 : 0
  subnet_id      = length(aws_subnet.public_b) > 0 ? aws_subnet.public_b[0].id : null
  route_table_id = aws_route_table.public.id
}

# Security group for EC2 (allow SSH from your IP, HTTP/HTTPS from anywhere)
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow SSH (custom), HTTP and HTTPS"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-sg" }
}

# Optional S3 bucket for frontend (boolean controlled below)
resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "frontend_bucket" {
  count = var.create_s3_bucket ? 1 : 0
  bucket = "${var.project_name}-frontend-${random_id.bucket_id.hex}"
  acl    = "public-read"
  website {
    index_document = "index.html"
    error_document = "index.html"
  }
  tags = { Name = "${var.project_name}-frontend-bucket" }
}

# EC2 instance for app (single instance deployment, demo)
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/ec2_user_data.sh")
  tags = { Name = "${var.project_name}-app" }
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }
}

# Optional RDS Postgres (toggleable)
resource "aws_db_subnet_group" "db_subnet" {
  count = var.create_rds ? 1 : 0
  name       = "${var.project_name}-db-subnet"
  subnet_ids = compact([aws_subnet.public_a.id] + (length(aws_subnet.public_b) > 0 ? [aws_subnet.public_b[0].id] : []))
}

resource "aws_db_instance" "postgres" {
  count               = var.create_rds ? 1 : 0
  identifier          = "${var.project_name}-postgres"
  engine              = "postgres"
  instance_class      = var.rds_instance_class
  allocated_storage   = var.rds_allocated_storage
  db_name             = var.rds_db_name
  username            = var.rds_username
  password            = var.rds_password
  db_subnet_group_name= aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  skip_final_snapshot = true
  publicly_accessible = false
  tags = { Name = "${var.project_name}-postgres" }
}
