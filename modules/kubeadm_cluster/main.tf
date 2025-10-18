# Kubeadm cluster module

# Obtener última AMI de Packer
data "aws_ami" "k8s_base" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["k8s-base-*"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["ec2.amazonaws.com"] }
  }
}

# Private Subnet
resource "aws_subnet" "k8s_private_subnet" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidr_block
  map_public_ip_on_launch = false
  availability_zone       = var.availability_zone

  tags = {
    Name = "${var.cluster_name}_private_subnet"
  }
}


# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.k8s_private_subnet.id
  route_table_id = var.private_route_table_id
}






# Control-plane IAM role
resource "aws_iam_role" "cp_role" {
  name               = "${var.name}-cp-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "cp_profile" {
  name = "${var.name}-cp-profile"
  role = aws_iam_role.cp_role.name
}

resource "aws_iam_role_policy" "cp_secrets" {
  role = aws_iam_role.cp_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name}/join-command*"
    }]
  })
}

# Worker IAM role
resource "aws_iam_role" "worker_role" {
  name               = "${var.name}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.name}-worker-profile"
  role = aws_iam_role.worker_role.name
}

resource "aws_iam_role_policy" "worker_secrets" {
  role = aws_iam_role.worker_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["secretsmanager:GetSecretValue"],
      Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name}/join-command*"
    }]
  })
}






# Control plane instance
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.k8s_base.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.k8s_private_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.cp_profile.name
  key_name               = var.key_name
  private_ip             = var.controlplane_private_ip

  user_data = templatefile("${path.module}/templates/control_plane_userdata.sh.tpl", {
    cluster_name = var.name
    pod_cidr     = var.pod_cidr
    service_cidr = var.service_cidr
  })

  source_dest_check = false # Disable Source/Destination Check

  tags = { Name = "${var.name}-control-plane" }
}

# Worker launch template
resource "aws_launch_template" "worker_lt" {
  name_prefix   = "${var.name}-worker-"
  ami = data.aws_ami.k8s_base.id
  instance_type = var.instance_type

  iam_instance_profile { name = aws_iam_instance_profile.worker_profile.name }

  user_data = base64encode(templatefile("${path.module}/templates/worker_userdata.sh.tpl", {
    cluster_name = var.name
  }))
}

# Worker ASG
resource "aws_autoscaling_group" "workers" {
  name                = "${var.name}-workers"
  desired_capacity    = var.worker_desired
  min_size            = var.worker_min
  max_size            = var.worker_max
  vpc_zone_identifier = [aws_subnet.k8s_private_subnet.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"



  launch_template {
    id      = aws_launch_template.worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-worker"
    propagate_at_launch = true
  }
  tag {
    key                 = "Cluster"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

}
