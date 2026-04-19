#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Bootstrap Keycloak (realm/roles/users), get tokens, and run smoke tests
# for frontend, API, Keycloak, and Postgres in k3s.
###############################################################################

# ------------------------------- Configuration ------------------------------ #
NAMESPACE="${NAMESPACE:-task-manager-api}"
SERVER_IP="${SERVER_IP:-83.69.249.206}"

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.${SERVER_IP}.nip.io}"
API_URL="${API_URL:-http://api.${SERVER_IP}.nip.io}"
FRONTEND_URL="${FRONTEND_URL:-http://app.${SERVER_IP}.nip.io}"

REALM="${REALM:-devsecops}"
CLIENT_ID="${CLIENT_ID:-task-manager-api}"

KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

ADMIN_USER="${ADMIN_USER:-admin1}"
DEV_USER="${DEV_USER:-dev1}"
VIEWER_USER="${VIEWER_USER:-viewer1}"
USERS_PASSWORD="${USERS_PASSWORD:-111}"

ADMIN_EMAIL="${ADMIN_EMAIL:-admin1@example.local}"
DEV_EMAIL="${DEV_EMAIL:-dev1@example.local}"
VIEWER_EMAIL="${VIEWER_EMAIL:-viewer1@example.local}"

API_DEPLOYMENT="${API_DEPLOYMENT:-api-deploy}"
FRONTEND_DEPLOYMENT="${FRONTEND_DEPLOYMENT:-frontend-deploy}"
KEYCLOAK_DEPLOYMENT="${KEYCLOAK_DEPLOYMENT:-keycloak}"
POSTGRES_STS="${POSTGRES_STS:-postgres-db}"

POSTGRES_SECRET_NAME="${POSTGRES_SECRET_NAME:-postgres-secret}"
POSTGRES_POD="${POSTGRES_POD:-postgres-db-0}"

# ------------------------------- Internals ---------------------------------- #
KEYCLOAK_URL="${KEYCLOAK_URL%/}"
API_URL="${API_URL%/}"
FRONTEND_URL="${FRONTEND_URL%/}"

TMP_DIR="$(mktemp -d)"
REQ_BODY="${TMP_DIR}/response.json"
trap 'rm -rf "${TMP_DIR}"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

log()  { printf '[INFO] %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

request() {
  # request METHOD URL [DATA] [TOKEN] [CONTENT_TYPE]
  local method="$1"
  local url="$2"
  local data="${3:-}"
  local token="${4:-}"
  local content_type="${5:-application/json}"
  local args=(
    -sS
    -o "${REQ_BODY}"
    -w "%{http_code}"
    -X "${method}"
    "${url}"
  )

  if [[ -n "${token}" ]]; then
    args+=(-H "Authorization: Bearer ${token}")
  fi
  if [[ -n "${data}" ]]; then
    args+=(-H "Content-Type: ${content_type}" --data "${data}")
  fi

  curl "${args[@]}" || true
}

get_admin_token() {
  local body
  body="$(curl -sS -X POST \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=admin-cli" \
    --data-urlencode "username=${KEYCLOAK_ADMIN_USER}" \
    --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}")"
  jq -r '.access_token // empty' <<<"${body}"
}

get_user_token() {
  local username="$1"
  local password="$2"
  local body
  body="$(curl -sS -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "username=${username}" \
    --data-urlencode "password=${password}")"
  jq -r '.access_token // empty' <<<"${body}"
}

ensure_realm() {
  local code
  code="$(request GET "${KEYCLOAK_URL}/admin/realms/${REALM}" "" "${KC_ADMIN_TOKEN}")"
  if [[ "${code}" == "200" ]]; then
    log "Realm '${REALM}' already exists"
    return
  fi
  if [[ "${code}" != "404" ]]; then
    die "Unexpected response while checking realm '${REALM}': HTTP ${code}"
  fi

  code="$(request POST "${KEYCLOAK_URL}/admin/realms" "{\"realm\":\"${REALM}\",\"enabled\":true}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "201" ]] || die "Failed to create realm '${REALM}' (HTTP ${code})"
  log "Realm '${REALM}' created"
}

ensure_client() {
  local clients_json client_internal_id
  clients_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}")"
  client_internal_id="$(jq -r '.[0].id // empty' <<<"${clients_json}")"

  if [[ -n "${client_internal_id}" ]]; then
    log "Client '${CLIENT_ID}' already exists"
    return
  fi

  local payload
  payload="$(cat <<JSON
{
  "clientId": "${CLIENT_ID}",
  "name": "${CLIENT_ID}",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": true,
  "directAccessGrantsEnabled": true,
  "standardFlowEnabled": true,
  "serviceAccountsEnabled": false,
  "redirectUris": ["*"],
  "webOrigins": ["*"]
}
JSON
)"
  local code
  code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" "${payload}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "201" ]] || die "Failed to create client '${CLIENT_ID}' (HTTP ${code})"
  log "Client '${CLIENT_ID}' created"
}

ensure_role() {
  local role="$1"
  local code
  code="$(request GET "${KEYCLOAK_URL}/admin/realms/${REALM}/roles/${role}" "" "${KC_ADMIN_TOKEN}")"
  if [[ "${code}" == "200" ]]; then
    log "Role '${role}' already exists"
    return
  fi
  if [[ "${code}" != "404" ]]; then
    die "Unexpected response while checking role '${role}': HTTP ${code}"
  fi
  code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/roles" "{\"name\":\"${role}\"}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "201" ]] || die "Failed to create role '${role}' (HTTP ${code})"
  log "Role '${role}' created"
}

ensure_user_with_role() {
  local username="$1"
  local email="$2"
  local role="$3"

  local users_json user_id
  users_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}&exact=true")"
  user_id="$(jq -r '.[0].id // empty' <<<"${users_json}")"

  if [[ -z "${user_id}" ]]; then
    local payload code
    payload="$(cat <<JSON
{
  "username": "${username}",
  "email": "${email}",
  "enabled": true,
  "emailVerified": true
}
JSON
)"
    code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" "${payload}" "${KC_ADMIN_TOKEN}")"
    [[ "${code}" == "201" ]] || die "Failed to create user '${username}' (HTTP ${code})"
    users_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}&exact=true")"
    user_id="$(jq -r '.[0].id // empty' <<<"${users_json}")"
    [[ -n "${user_id}" ]] || die "User '${username}' created but ID not found"
    log "User '${username}' created"
  else
    log "User '${username}' already exists"
  fi

  local pass_payload code
  pass_payload="$(cat <<JSON
{
  "type": "password",
  "value": "${USERS_PASSWORD}",
  "temporary": false
}
JSON
)"
  code="$(request PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}/reset-password" "${pass_payload}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to set password for '${username}' (HTTP ${code})"

  local role_json
  role_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/roles/${role}")"
  [[ "$(jq -r '.name // empty' <<<"${role_json}")" == "${role}" ]] || die "Failed to fetch role '${role}' representation"
  code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}/role-mappings/realm" "[${role_json}]" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to assign role '${role}' to '${username}' (HTTP ${code})"
  log "User '${username}' is configured with role '${role}'"
}

test_rollout() {
  local kind_name="$1"
  if kubectl -n "${NAMESPACE}" rollout status "${kind_name}" --timeout=180s >/dev/null; then
    pass "Rollout: ${kind_name}"
  else
    fail "Rollout: ${kind_name}"
  fi
}

test_http_code() {
  local name="$1"
  local expected="$2"
  local url="$3"
  local token="${4:-}"
  local code

  if [[ -n "${token}" ]]; then
    code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" -H "Authorization: Bearer ${token}" "${url}" || true)"
  else
    code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" "${url}" || true)"
  fi

  if [[ "${code}" == "${expected}" ]]; then
    pass "${name} -> HTTP ${expected}"
  else
    fail "${name} -> expected ${expected}, got ${code}"
    if [[ -s "${REQ_BODY}" ]]; then
      sed 's/^/       /' "${REQ_BODY}" || true
    fi
  fi
}

test_service_endpoints() {
  local svc="$1"
  local endpoints
  endpoints="$(kubectl -n "${NAMESPACE}" get endpoints "${svc}" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true)"
  if [[ -n "${endpoints}" ]]; then
    pass "Endpoints present for ${svc}: ${endpoints}"
  else
    fail "No endpoints for service ${svc}"
  fi
}

test_postgres_query() {
  local pg_user pg_pass pg_db out
  pg_user="$(kubectl -n "${NAMESPACE}" get secret "${POSTGRES_SECRET_NAME}" -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)"
  pg_pass="$(kubectl -n "${NAMESPACE}" get secret "${POSTGRES_SECRET_NAME}" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
  pg_db="$(kubectl -n "${NAMESPACE}" get secret "${POSTGRES_SECRET_NAME}" -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)"
  out="$(kubectl -n "${NAMESPACE}" exec "${POSTGRES_POD}" -- env PGPASSWORD="${pg_pass}" psql -U "${pg_user}" -d "${pg_db}" -tAc "select 1;" 2>/dev/null || true)"
  if [[ "${out}" == "1" ]]; then
    pass "Postgres connectivity query (select 1)"
  else
    fail "Postgres connectivity query failed"
  fi
}

# --------------------------------- Start ------------------------------------ #
require_cmd kubectl
require_cmd curl
require_cmd jq
require_cmd base64

log "Using namespace: ${NAMESPACE}"
log "Keycloak URL: ${KEYCLOAK_URL}"
log "API URL: ${API_URL}"
log "Frontend URL: ${FRONTEND_URL}"

log "Waiting for core workloads..."
test_rollout "deployment/${KEYCLOAK_DEPLOYMENT}"
test_rollout "deployment/${API_DEPLOYMENT}"
test_rollout "deployment/${FRONTEND_DEPLOYMENT}"
test_rollout "statefulset/${POSTGRES_STS}"

log "Bootstrapping Keycloak..."
KC_ADMIN_TOKEN="$(get_admin_token)"
[[ -n "${KC_ADMIN_TOKEN}" ]] || die "Cannot obtain Keycloak admin token. Check KEYCLOAK_URL/admin credentials."

ensure_realm
ensure_client
ensure_role "admin"
ensure_role "developer"
ensure_role "viewer"
ensure_user_with_role "${ADMIN_USER}" "${ADMIN_EMAIL}" "admin"
ensure_user_with_role "${DEV_USER}" "${DEV_EMAIL}" "developer"
ensure_user_with_role "${VIEWER_USER}" "${VIEWER_EMAIL}" "viewer"

log "Running service-level checks..."
test_service_endpoints "postgres-svc"
test_service_endpoints "keycloak-svc"
test_service_endpoints "api-svc"
test_service_endpoints "frontend-svc"
test_postgres_query

log "Running HTTP checks..."
test_http_code "Frontend root" "200" "${FRONTEND_URL}/"
test_http_code "API health" "200" "${API_URL}/health"
test_http_code "Keycloak OIDC discovery" "200" "${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration"

log "Getting user tokens..."
ADMIN_TOKEN="$(get_user_token "${ADMIN_USER}" "${USERS_PASSWORD}")"
DEV_TOKEN="$(get_user_token "${DEV_USER}" "${USERS_PASSWORD}")"
VIEWER_TOKEN="$(get_user_token "${VIEWER_USER}" "${USERS_PASSWORD}")"

[[ -n "${ADMIN_TOKEN}" ]]  && pass "Token for ${ADMIN_USER}"  || fail "Failed to get token for ${ADMIN_USER}"
[[ -n "${DEV_TOKEN}" ]]    && pass "Token for ${DEV_USER}"    || fail "Failed to get token for ${DEV_USER}"
[[ -n "${VIEWER_TOKEN}" ]] && pass "Token for ${VIEWER_USER}" || fail "Failed to get token for ${VIEWER_USER}"

if [[ -n "${ADMIN_TOKEN}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" -H "Authorization: Bearer ${ADMIN_TOKEN}" "${API_URL}/me" || true)"
  role="$(jq -r '.role // empty' "${REQ_BODY}" 2>/dev/null || true)"
  [[ "${code}" == "200" && "${role}" == "admin" ]] && pass "/me for ${ADMIN_USER} returns admin" || fail "/me for ${ADMIN_USER} failed (HTTP ${code}, role=${role})"
fi

if [[ -n "${DEV_TOKEN}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" -H "Authorization: Bearer ${DEV_TOKEN}" "${API_URL}/me" || true)"
  role="$(jq -r '.role // empty' "${REQ_BODY}" 2>/dev/null || true)"
  [[ "${code}" == "200" && "${role}" == "developer" ]] && pass "/me for ${DEV_USER} returns developer" || fail "/me for ${DEV_USER} failed (HTTP ${code}, role=${role})"
fi

if [[ -n "${VIEWER_TOKEN}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" -H "Authorization: Bearer ${VIEWER_TOKEN}" "${API_URL}/me" || true)"
  role="$(jq -r '.role // empty' "${REQ_BODY}" 2>/dev/null || true)"
  [[ "${code}" == "200" && "${role}" == "viewer" ]] && pass "/me for ${VIEWER_USER} returns viewer" || fail "/me for ${VIEWER_USER} failed (HTTP ${code}, role=${role})"
fi

log "Running RBAC tests..."
test_http_code "Unauthorized /me" "401" "${API_URL}/me"

if [[ -n "${VIEWER_TOKEN}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" \
    -H "Authorization: Bearer ${VIEWER_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"title":"viewer-denied","description":"rbac","status":"new"}' \
    "${API_URL}/tasks" || true)"
  [[ "${code}" == "403" ]] && pass "Viewer cannot create task (403)" || fail "Viewer create task expected 403, got ${code}"
fi

ADMIN_TASK_ID=""
if [[ -n "${ADMIN_TOKEN}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"admin-smoke-$(date +%s)\",\"description\":\"smoke\",\"status\":\"new\"}" \
    "${API_URL}/tasks" || true)"
  if [[ "${code}" == "201" ]]; then
    ADMIN_TASK_ID="$(jq -r '.id // empty' "${REQ_BODY}")"
    pass "Admin can create task (201)"
  else
    fail "Admin create task expected 201, got ${code}"
  fi
fi

DEV_TASK_ID=""
if [[ -n "${DEV_TOKEN}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" \
    -H "Authorization: Bearer ${DEV_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"dev-smoke-$(date +%s)\",\"description\":\"smoke\",\"status\":\"new\"}" \
    "${API_URL}/tasks" || true)"
  if [[ "${code}" == "201" ]]; then
    DEV_TASK_ID="$(jq -r '.id // empty' "${REQ_BODY}")"
    pass "Developer can create task (201)"
  else
    fail "Developer create task expected 201, got ${code}"
  fi
fi

if [[ -n "${DEV_TOKEN}" && -n "${DEV_TASK_ID}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer ${DEV_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"status":"done"}' \
    "${API_URL}/tasks/${DEV_TASK_ID}" || true)"
  [[ "${code}" == "200" ]] && pass "Developer can update own task (200)" || fail "Developer update own task expected 200, got ${code}"
fi

if [[ -n "${VIEWER_TOKEN}" && -n "${DEV_TASK_ID}" ]]; then
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer ${VIEWER_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"status":"archived"}' \
    "${API_URL}/tasks/${DEV_TASK_ID}" || true)"
  [[ "${code}" == "403" ]] && pass "Viewer cannot update task (403)" || fail "Viewer update task expected 403, got ${code}"
fi

# cleanup created tasks (best effort)
if [[ -n "${ADMIN_TOKEN}" && -n "${ADMIN_TASK_ID}" ]]; then
  curl -sS -o /dev/null -w "" -X DELETE -H "Authorization: Bearer ${ADMIN_TOKEN}" "${API_URL}/tasks/${ADMIN_TASK_ID}" || true
fi
if [[ -n "${ADMIN_TOKEN}" && -n "${DEV_TASK_ID}" ]]; then
  curl -sS -o /dev/null -w "" -X DELETE -H "Authorization: Bearer ${ADMIN_TOKEN}" "${API_URL}/tasks/${DEV_TASK_ID}" || true
fi

echo
echo "==================== RESULT ===================="
echo "Passed: ${PASS_COUNT}"
echo "Failed: ${FAIL_COUNT}"
echo "================================================"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi

