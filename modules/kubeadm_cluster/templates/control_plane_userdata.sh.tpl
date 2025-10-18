#!/bin/bash
set -e

# kubeadm init
kubeadm init --pod-network-cidr=${pod_cidr} --service-cidr=${service_cidr}

mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

JOIN_CMD=$(kubeadm token create --ttl 0 --print-join-command)

aws secretsmanager describe-secret --secret-id "${cluster_name}/join-command" >/dev/null 2>&1   && aws secretsmanager put-secret-value --secret-id "${cluster_name}/join-command" --secret-string "$JOIN_CMD"   || aws secretsmanager create-secret --name "${cluster_name}/join-command" --secret-string "$JOIN_CMD"
