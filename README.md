# terraform-kubeadm-multicluster

This Terraform project provisions multiple self-managed Kubernetes clusters on AWS using kubeadm and Auto Scaling Groups (ASGs).
Each cluster has:
- 1 control-plane node
- Worker Auto Scaling Group
- Pod CIDR and Service CIDR configurable per cluster
- Permanent kubeadm join command stored securely in AWS Secrets Manager

See `terraform.tfvars` for cluster definitions.
