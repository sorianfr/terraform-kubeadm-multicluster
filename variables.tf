variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1" # Optional default value
}

variable "availability_zone" {
  type        = string
  default     = "us-east-1a"
  description = "Availability zone for the public subnet"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the shared VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "CIDR block for the shared Public Subnet"
  default     = "10.0.1.0/24"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
  default     = "ami-0360c520857e3138f" # Ubuntu 20.04 in us-east-1; change for your region/OS preference

}

variable "instance_type" {
  default = "c7i-flex.large"
}

variable "clusters" {
  description = "List of cluster definitions"
  type = list(object({
    name           = string
    control_ami    = string 
    worker_ami     = string
    instance_type  = string
    worker_min     = number
    worker_max     = number
    worker_desired = number
    pod_cidr       = string
    service_cidr   = string
    worker_ebs_volumes = optional(list(object({
      volume_size = number
      volume_type = string
      device_name = string
    })), []) # default to empty list if not provided
  }))
}


variable "copy_files_to_bastion" {
  description = "List of local files that should be copied to the bastion host"
  type        = list(string)
  default = [
    "my_k8s_key.pem"
  ]
}
