#!/bin/bash
set -e

apt-get update -y
apt-get install -y awscli containerd apt-transport-https ca-certificates curl gnupg lsb-release

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm
systemctl enable kubelet

until JOIN_CMD=$(aws secretsmanager get-secret-value --secret-id "${cluster_name}/join-command" --query SecretString --output text 2>/dev/null); do
  echo "Join command not ready; sleeping 30s..."
  sleep 30
done

echo "Joining cluster..."
$JOIN_CMD
