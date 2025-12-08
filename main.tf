provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "rat-pay"
      ManagedBy = "Terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for Minikube"
  type        = string
  default     = "t3.medium" # Minikube requires min 2 CPU and 2GB RAM
}

variable "key_pair_name" {
  description = "Name of AWS Key Pair for EC2 access"
  type        = string
  default     = "rat-pay"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "83.175.182.175/32"
}

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = {
    Name = var.key_pair_name
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${var.key_pair_name}.pem"
  file_permission = "0400"
}

# Data source for latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "minikube" {
  name        = "rat-pay-minikube-sg"
  description = "Security group for Minikube EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
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
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rat-pay-minikube-sg"
  }
}

resource "aws_instance" "rat-pay-minikube" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.minikube.id]
  key_name               = aws_key_pair.ec2_key.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = false
  }

  tags = {
    Name = "rat-pay-minikube"
  }
}

resource "aws_eip" "minikube" {
  domain    = "vpc"
  instance  = aws_instance.rat-pay-minikube.id

  tags = {
    Name = "rat-pay-minikube-eip"
  }
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.rat-pay-minikube.id
}

output "public_ip" {
  description = "Static public IP (Elastic IP) of the EC2 instance"
  value       = aws_eip.minikube.public_ip
}

output "public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_eip.minikube.public_dns
}

output "ssh_command" {
  description = "SSH command to connect to EC2 instance"
  value       = "ssh -i ${var.key_pair_name}.pem ubuntu@${aws_eip.minikube.public_ip}"
}

output "private_key_filename" {
  description = "Filename of the generated private key"
  value       = local_file.private_key.filename
  sensitive   = false
}
