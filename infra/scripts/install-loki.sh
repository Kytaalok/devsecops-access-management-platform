#!/usr/bin/env bash
# Устанавливает / обновляет Loki + Promtail в namespace monitoring.
# Loki — централизованное хранилище логов.
# Promtail — агент сбора логов (DaemonSet на каждой ноде).
#
# Использование:
#   bash infra/scripts/install-loki.sh
#
# Требования:
#   - kube-prometheus-stack уже установлен (install-monitoring.sh)
#   - namespace monitoring существует

set -Eeuo pipefail

NAMESPACE="monitoring"
HELM_RELEASE="loki-stack"
VALUES_FILE="infra/k3s/monitoring/loki-values.yaml"
DATASOURCE_MANIFEST="infra/k3s/monitoring/loki-datasource.yaml"
DASHBOARD_MANIFEST="infra/k3s/monitoring/grafana-security-dashboard-cm.yaml"

log()  { printf '[INFO] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ -f "${VALUES_FILE}" ]]       || die "Not found: ${VALUES_FILE}"
[[ -f "${DATASOURCE_MANIFEST}" ]] || die "Not found: ${DATASOURCE_MANIFEST}"
[[ -f "${DASHBOARD_MANIFEST}" ]]  || die "Not found: ${DASHBOARD_MANIFEST}"

kubectl get namespace "${NAMESPACE}" &>/dev/null || \
  die "Namespace '${NAMESPACE}' not found — run install-monitoring.sh first"

# ── Helm repo ─────────────────────────────────────────────────────────────────
if ! helm repo list 2>/dev/null | grep -q '^grafana'; then
  helm repo add grafana https://grafana.github.io/helm-charts
  log "Helm repo grafana added"
fi
helm repo update grafana
log "Helm repo updated"

# ── Install / upgrade ─────────────────────────────────────────────────────────
log "Installing/upgrading ${HELM_RELEASE} in ${NAMESPACE}..."
helm upgrade --install "${HELM_RELEASE}" grafana/loki-stack \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --timeout 5m \
  --wait

log "loki-stack deployed"
# Примечание: loki.isDefault=false задан в values.yaml — Prometheus остаётся default datasource

# ── Security logs dashboard ConfigMap ─────────────────────────────────────────
kubectl apply -f "${DASHBOARD_MANIFEST}"
log "Security logs dashboard ConfigMap applied"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo " Loki endpoint:   http://loki-stack.monitoring.svc:3100"
echo " Promtail:        DaemonSet — работает на всех нодах"
echo " Grafana:         datasource 'Loki' (uid: loki) добавлен"
echo " Dashboard:       'Security Events — Auth, AuthZ & Access Logs'"
echo "=================================================="
echo ""
kubectl get pods -n "${NAMESPACE}" | grep -E "loki|promtail"
