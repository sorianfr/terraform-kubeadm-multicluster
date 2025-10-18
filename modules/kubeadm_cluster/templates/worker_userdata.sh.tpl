#!/bin/bash
set -e

until JOIN_CMD=$(aws secretsmanager get-secret-value --secret-id "${cluster_name}/join-command" --query SecretString --output text 2>/dev/null); do
  echo "Join command not ready; sleeping 30s..."
  sleep 30
done

echo "Joining cluster..."
$JOIN_CMD
