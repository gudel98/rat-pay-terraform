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

variable "repository_url" {
  description = "URL of the application repository"
  type        = string
  default     = "https://github.com/gudel98/rat-pay.git"
}
