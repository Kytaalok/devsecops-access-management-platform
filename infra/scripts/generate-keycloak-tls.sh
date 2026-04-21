#!/usr/bin/env bash
# Использование:
#   bash infra/scripts/generate-keycloak-tls.sh [SERVER_IP]
# По умолчанию SERVER_IP=master_ip

set -euo pipefail

SERVER_IP="${1:-83.69.249.206}"
HOSTNAME="keycloak.${SERVER_IP}.nip.io"
NAMESPACE="task-manager-api"
OUT_DIR="infra/tls"
K3S_CA_DEST="/etc/rancher/k3s/keycloak-ca.crt"

echo "[INFO] Generate TLS for ${HOSTNAME}"

mkdir -p "${OUT_DIR}"

# CA
openssl genrsa -out "${OUT_DIR}/ca.key" 4096 2>/dev/null
openssl req -new -x509 -days 3650 -key "${OUT_DIR}/ca.key" \
  -out "${OUT_DIR}/ca.crt" \
  -subj "/CN=DiplomaCA/O=Diploma/C=RU" 2>/dev/null

# Keycloak cert
openssl genrsa -out "${OUT_DIR}/keycloak.key" 2048 2>/dev/null
openssl req -new -key "${OUT_DIR}/keycloak.key" \
  -out "${OUT_DIR}/keycloak.csr" \
  -subj "/CN=${HOSTNAME}/O=Diploma/C=RU" 2>/dev/null

cat > "${OUT_DIR}/keycloak.ext" << EXTEOF
[SAN]
subjectAltName=DNS:${HOSTNAME}
EXTEOF

openssl x509 -req -days 3650 \
  -in "${OUT_DIR}/keycloak.csr" \
  -CA "${OUT_DIR}/ca.crt" \
  -CAkey "${OUT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${OUT_DIR}/keycloak.crt" \
  -extfile "${OUT_DIR}/keycloak.ext" \
  -extensions SAN 2>/dev/null

echo "[INFO] Certs done in ${OUT_DIR}/"

# Kubernetes secret
kubectl create secret tls keycloak-tls-secret \
  -n "${NAMESPACE}" \
  --cert="${OUT_DIR}/keycloak.crt" \
  --key="${OUT_DIR}/keycloak.key" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "[INFO] Secret keycloak-tls-secret применён"

# CA для k3s kube-apiserver
sudo cp "${OUT_DIR}/ca.crt" "${K3S_CA_DEST}"
sudo chmod 644 "${K3S_CA_DEST}"
echo "[INFO] CA copied in ${K3S_CA_DEST}"

echo "[OK] Done. k3s reboot:"
echo "     sudo systemctl restart k3s"
