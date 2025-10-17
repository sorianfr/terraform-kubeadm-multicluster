#!/bin/bash
set -e

apt-get update -y
apt-get install -y awscli containerd apt-transport-https ca-certificates curl gnupg lsb-release

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# Sysctl params
cat <<EOF >/etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
modprobe br_netfilter || true
sysctl --system

# Install kubeadm/kubelet/kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
systemctl enable kubelet

# kubeadm init
kubeadm init --pod-network-cidr=${pod_cidr} --service-cidr=${service_cidr}

mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

JOIN_CMD=$(kubeadm token create --ttl 0 --print-join-command)

aws secretsmanager describe-secret --secret-id "${cluster_name}/join-command" >/dev/null 2>&1   && aws secretsmanager put-secret-value --secret-id "${cluster_name}/join-command" --secret-string "$JOIN_CMD"   || aws secretsmanager create-secret --name "${cluster_name}/join-command" --secret-string "$JOIN_CMD"
