terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Index clusters by name for reuse
locals {
  clusters_by_name = {
    for cluster in var.clusters :
    cluster.name => cluster
  }
}



# Generate a TLS private key
resource "tls_private_key" "k8s_key_pair" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Key Pair
resource "aws_key_pair" "k8s_key_pair" {
  key_name   = "my_k8s_key"
  public_key = tls_private_key.k8s_key_pair.public_key_openssh
}

# Save the private key locally
resource "local_file" "save_private_key" {
  filename        = "${path.module}/my_k8s_key.pem"
  content         = tls_private_key.k8s_key_pair.private_key_pem
  file_permission = "0600"

}

# Output the private key (for reference or debugging)
output "k8s_private_key" {
  value     = tls_private_key.k8s_key_pair.private_key_pem
  sensitive = true
}


# VPC for All Clusters
resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main_vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidr_block
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone

  tags = {
    Name = "public_subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main_igw"
  }
}


# Route Table for Public Subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public_rt"
  }
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Elastic IP for Shared NAT Gateway
resource "aws_eip" "shared_nat_eip" {

  tags = {
    Name = "shared_nat_eip"
  }
}

# Shared NAT Gateway
resource "aws_nat_gateway" "shared_nat_gw" {
  allocation_id = aws_eip.shared_nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "shared_nat_gw"
  }

  depends_on = [aws_eip.shared_nat_eip]
}

# Shared Private Route Table
resource "aws_route_table" "shared_private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.shared_nat_gw.id
  }

  tags = {
    Name = "shared_private_rt"
  }
}

# Shared Bastion Host (uses public subnet)
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = aws_key_pair.k8s_key_pair.key_name

  tags = {
    Name = "shared_bastion"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install -y curl wget unzip jq",
      "sudo apt install -y ansible", # Install Ansible
      "curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl",
      "chmod +x kubectl",
      "sudo mv kubectl /usr/local/bin/",
      "kubectl version --client" # Verify kubectl installation
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.k8s_key_pair.private_key_pem
    host        = self.public_ip
  }

  depends_on = [local_file.save_private_key]

}

# Shared Bastion Host Security Group
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Adjust for production environments
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion_sg"
  }
}

# IAM Role for EC2 instances to access S3 and other resources
resource "aws_iam_role" "AmazonEBSCSIDriverRole" {
  name = "AmazonEBSCSIDriverRole"

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

# Attach policy to role
resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.AmazonEBSCSIDriverRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
# Create instance profile to be attached to ec2 instances. 
resource "aws_iam_instance_profile" "AmazonEBS_instance_profile" {
  name = "AmazonEBS_instance_profile"
  role = aws_iam_role.AmazonEBSCSIDriverRole.name
}


module "clusters" {
  for_each = { for c in var.clusters : c.name => c }
  source   = "./modules/kubeadm_cluster"

  name            = each.value.name
  region          = each.value.region
  vpc_id          = aws_vpc.main_vpc.id
  availability_zone = var.availability_zone
  private_route_table_id = aws_route_table.shared_private_rt.id
  key_name               = aws_key_pair.k8s_key_pair.key_name
  public_sg_id           = aws_security_group.bastion_sg.id
  bastion_public_dns     = aws_instance.bastion.public_dns
  control_ami     = each.value.control_ami
  worker_ami      = each.value.worker_ami
  instance_type   = each.value.instance_type
  worker_min      = each.value.worker_min
  worker_max      = each.value.worker_max
  worker_desired  = each.value.worker_desired
  pod_cidr        = each.value.pod_cidr
  service_cidr    = each.value.service_cidr
}

  private_subnet_cidr_block = each.value.private_subnet_cidr_block
  controlplane_private_ip   = each.value.controlplane_private_ip
  pod_subnet                = each.value.pod_subnet
  service_cidr              = each.value.service_cidr



