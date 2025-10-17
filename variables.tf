variable "clusters" {
  description = "List of cluster definitions"
  type = list(object({
    name           = string
    region         = string
    vpc_id         = string
    subnets        = list(string)
    control_ami    = string
    worker_ami     = string
    instance_type  = string
    worker_min     = number
    worker_max     = number
    worker_desired = number
    pod_cidr       = string
    service_cidr   = string
  }))
}
