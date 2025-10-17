terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "clusters" {
  for_each = { for c in var.clusters : c.name => c }
  source   = "./modules/kubeadm_cluster"

  name            = each.value.name
  region          = each.value.region
  vpc_id          = each.value.vpc_id
  subnets         = each.value.subnets
  control_ami     = each.value.control_ami
  worker_ami      = each.value.worker_ami
  instance_type   = each.value.instance_type
  worker_min      = each.value.worker_min
  worker_max      = each.value.worker_max
  worker_desired  = each.value.worker_desired
  pod_cidr        = each.value.pod_cidr
  service_cidr    = each.value.service_cidr
}
