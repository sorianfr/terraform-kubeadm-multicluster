variable "name" {}
variable "region" {}
variable "vpc_id" {}
variable "subnets" { type = list(string) }
variable "control_ami" {}
variable "worker_ami" {}
variable "instance_type" {}
variable "worker_min" { default = 1 }
variable "worker_max" { default = 3 }
variable "worker_desired" { default = 1 }
variable "pod_cidr" { description = "Pod CIDR range" }
variable "service_cidr" { description = "Service CIDR range" }
