# Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "rat-pay"
      ManagedBy = "Terraform"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for Minikube"
  type        = string
  default     = "t3.medium" # Minikube needs at least 2 CPU and 2GB RAM
}

variable "key_pair_name" {
  description = "Name of AWS Key Pair for EC2 access"
  type        = string
  default     = "rat-pay"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "192.168.0.1"
}

# Generate private key
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS Key Pair
resource "aws_key_pair" "ec2_key" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = {
    Name = var.key_pair_name
  }
}

# Save private key to file
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

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for EC2
resource "aws_security_group" "minikube" {
  name        = "rat-pay-minikube-sg"
  description = "Security group for Minikube EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access
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

# Read user data script
data "local_file" "minikube_setup" {
  filename = "${path.module}/minikube-setup.sh"
}

# EC2 Instance for Minikube
resource "aws_instance" "rat-pay-minikube" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.minikube.id]
  key_name               = aws_key_pair.ec2_key.key_name
  user_data              = data.local_file.minikube_setup.content

  # Root volume configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = 20 # 20GB is sufficient for Ubuntu + Minikube + apps
    encrypted   = false
  }

  tags = {
    Name = "rat-pay-minikube"
  }
}

# Elastic IP for static public IP
resource "aws_eip" "minikube" {
  domain    = "vpc"
  instance  = aws_instance.rat-pay-minikube.id

  tags = {
    Name = "rat-pay-minikube-eip"
  }
}

# Run setup script on the instance (only if not already run)
resource "null_resource" "minikube_setup" {
  # Only run if the minikube-setup.sh script doesn't exist
  triggers = {
    instance_id = aws_instance.rat-pay-minikube.id
    script_hash = data.local_file.minikube_setup.content_base64sha256
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/minikube-setup.sh"
    destination = "/tmp/minikube-setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/minikube-setup.sh",
      "sudo /tmp/minikube-setup.sh",
      "rm /tmp/minikube-setup.sh"
    ]
  }

  depends_on = [aws_eip.minikube]
}

# Outputs
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

