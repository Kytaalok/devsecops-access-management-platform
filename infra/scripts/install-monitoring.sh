#!/usr/bin/env bash
#
# Использование:
#   bash infra/scripts/install-monitoring.sh [SERVER_IP]
#
# Требования:
#   - infra/k3s/monitoring/secrets/grafana-admin.env  (содержит grafana-admin-password=...)
#   - infra/tls/wildcard.crt + infra/tls/wildcard.key (создаются generate-keycloak-tls.sh)

set -Eeuo pipefail

SERVER_IP="${1:-83.69.249.206}"
NAMESPACE="monitoring"
HELM_RELEASE="kube-prometheus-stack"
VALUES_FILE="infra/k3s/monitoring/values.yaml"
SECRETS_FILE="${GRAFANA_SECRETS_FILE:-infra/k3s/monitoring/secrets/grafana-admin.env}"
TLS_CERT="infra/tls/wildcard.crt"
TLS_KEY="infra/tls/wildcard.key"

log()  { printf '[INFO] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ -f "${VALUES_FILE}" ]]  || die "Not found: ${VALUES_FILE}"
[[ -f "${TLS_CERT}" ]]     || die "Not found: ${TLS_CERT} — run generate-keycloak-tls.sh first"
[[ -f "${TLS_KEY}" ]]      || die "Not found: ${TLS_KEY}"

# ── Grafana admin password ────────────────────────────────────────────────────
if [[ -f "${SECRETS_FILE}" ]]; then
  GRAFANA_ADMIN_PASSWORD="$(grep '^grafana-admin-password=' "${SECRETS_FILE}" | cut -d= -f2-)"
fi
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?ERROR: set grafana-admin-password in ${SECRETS_FILE}}"

# ── Namespace ─────────────────────────────────────────────────────────────────
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  kubectl create namespace "${NAMESPACE}"
  log "Namespace '${NAMESPACE}' created"
else
  log "Namespace '${NAMESPACE}' already exists"
fi

# ── TLS secret for Grafana ────────────────────────────────────────────────────
kubectl create secret tls grafana-tls-secret \
  -n "${NAMESPACE}" \
  --cert="${TLS_CERT}" \
  --key="${TLS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
log "Secret grafana-tls-secret applied in ${NAMESPACE}"

# ── Helm repo ─────────────────────────────────────────────────────────────────
if ! helm repo list 2>/dev/null | grep -q prometheus-community; then
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  log "Helm repo prometheus-community added"
fi
helm repo update prometheus-community
log "Helm repo updated"

# ── Install / upgrade ─────────────────────────────────────────────────────────
log "Installing/upgrading ${HELM_RELEASE} in ${NAMESPACE}..."
helm upgrade --install "${HELM_RELEASE}" prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set "grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD}" \
  --set "grafana.ingress.hosts[0]=grafana.${SERVER_IP}.nip.io" \
  --set "grafana.ingress.tls[0].hosts[0]=grafana.${SERVER_IP}.nip.io" \
  --atomic \
  --timeout 10m \
  --wait

log "kube-prometheus-stack deployed"

# ── ServiceMonitor для API ────────────────────────────────────────────────────
kubectl apply -f infra/k3s/monitoring/servicemonitor-api.yaml
log "ServiceMonitor for task-manager-api applied"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo " Grafana: https://grafana.${SERVER_IP}.nip.io"
echo " Login:   admin / ${GRAFANA_ADMIN_PASSWORD}"
echo "=================================================="
echo ""
kubectl get pods -n "${NAMESPACE}"
