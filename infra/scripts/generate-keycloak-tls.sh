#!/usr/bin/env bash
# Генерирует wildcard-сертификат *.SERVER_IP.nip.io, подписанный самодельным CA.
# Создаёт TLS-секреты в namespace task-manager-api и cicd.
# CA копируется в /etc/rancher/k3s/keycloak-ca.crt для k3s OIDC.
#
# Использование:
#   bash infra/scripts/generate-keycloak-tls.sh [SERVER_IP]

set -euo pipefail

SERVER_IP="${1:-83.69.249.206}"
WILDCARD="*.${SERVER_IP}.nip.io"
NAMESPACE="task-manager-api"
CICD_NAMESPACE="cicd"
OUT_DIR="infra/tls"
K3S_CA_DEST="/etc/rancher/k3s/keycloak-ca.crt"

echo "[INFO] Generating wildcard TLS for ${WILDCARD}"

mkdir -p "${OUT_DIR}"

# ── CA ────────────────────────────────────────────────────────────────────────
openssl genrsa -out "${OUT_DIR}/ca.key" 4096 2>/dev/null
openssl req -new -x509 -days 3650 -key "${OUT_DIR}/ca.key" \
  -out "${OUT_DIR}/ca.crt" \
  -subj "/CN=DiplomaCA/O=Diploma/C=RU" 2>/dev/null
echo "[INFO] CA generated"

# ── Wildcard cert ─────────────────────────────────────────────────────────────
openssl genrsa -out "${OUT_DIR}/wildcard.key" 2048 2>/dev/null
openssl req -new -key "${OUT_DIR}/wildcard.key" \
  -out "${OUT_DIR}/wildcard.csr" \
  -subj "/CN=${WILDCARD}/O=Diploma/C=RU" 2>/dev/null

cat > "${OUT_DIR}/wildcard.ext" <<EXTEOF
[SAN]
subjectAltName=DNS:${WILDCARD},DNS:${SERVER_IP}.nip.io
EXTEOF

openssl x509 -req -days 3650 \
  -in "${OUT_DIR}/wildcard.csr" \
  -CA "${OUT_DIR}/ca.crt" \
  -CAkey "${OUT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${OUT_DIR}/wildcard.crt" \
  -extfile "${OUT_DIR}/wildcard.ext" \
  -extensions SAN 2>/dev/null
echo "[INFO] Wildcard cert generated: ${OUT_DIR}/wildcard.crt"

# ── Kubernetes TLS secrets ────────────────────────────────────────────────────
# task-manager-api: keycloak-tls-secret (используется keycloak-ingress-tls.yaml)
kubectl create secret tls keycloak-tls-secret \
  -n "${NAMESPACE}" \
  --cert="${OUT_DIR}/wildcard.crt" \
  --key="${OUT_DIR}/wildcard.key" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "[INFO] Secret keycloak-tls-secret applied in ${NAMESPACE}"

# cicd: jenkins-tls-secret (используется jenkins-ingress-tls.yaml)
kubectl create secret tls jenkins-tls-secret \
  -n "${CICD_NAMESPACE}" \
  --cert="${OUT_DIR}/wildcard.crt" \
  --key="${OUT_DIR}/wildcard.key" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "[INFO] Secret jenkins-tls-secret applied in ${CICD_NAMESPACE}"

# ── CA для k3s kube-apiserver (OIDC) ─────────────────────────────────────────
sudo cp "${OUT_DIR}/ca.crt" "${K3S_CA_DEST}"
sudo chmod 644 "${K3S_CA_DEST}"
echo "[INFO] CA copied to ${K3S_CA_DEST}"

echo ""
echo "[OK] Done. Если CA изменился — перезапусти k3s:"
echo "     sudo systemctl restart k3s"
