# Приложение Г. Bootstrap- и smoke-скрипт

В приложении приведен скрипт автоматической настройки Keycloak и комплексной проверки стенда: создание realm, клиентов, ролей и пользователей; получение токенов; HTTP smoke-тесты; проверка PostgreSQL; API RBAC; Kubernetes RBAC; проверка Jenkins OIDC.

### Файл `infra/scripts/bootstrap_keycloak_and_smoke_test.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Bootstrap Keycloak (realm/roles/users/clients/mappers), get tokens, and run
# smoke tests + Kubernetes RBAC tests for DevSecOps diploma infrastructure.
###############################################################################

# ------------------------------- Configuration ------------------------------ #
NAMESPACE="${NAMESPACE:-task-manager-api}"
SERVER_IP="${SERVER_IP:-83.69.249.206}"
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-cicd}"

KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.${SERVER_IP}.nip.io}"
KEYCLOAK_CA_CERT="${KEYCLOAK_CA_CERT:-/etc/rancher/k3s/keycloak-ca.crt}"
API_URL="${API_URL:-http://api.${SERVER_IP}.nip.io}"
FRONTEND_URL="${FRONTEND_URL:-http://app.${SERVER_IP}.nip.io}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.${SERVER_IP}.nip.io}"

REALM="${REALM:-devsecops}"
CLIENT_ID="${CLIENT_ID:-task-manager-api}"
JENKINS_CLIENT_ID="${JENKINS_CLIENT_ID:-jenkins}"

# Keycloak admin credentials — читаем из secrets-файла если он есть,
# иначе берём из переменных окружения (для запуска из Jenkins pod).
_KC_SECRETS_FILE="${KC_SECRETS_FILE:-infra/k3s/jenkins/secrets/jenkins-admin.env}"
if [[ -f "${_KC_SECRETS_FILE}" ]]; then
  _kc_user="$(grep '^jenkins-admin-user='  "${_KC_SECRETS_FILE}" | cut -d= -f2-)"
  _kc_pass="$(grep '^jenkins-admin-password=' "${_KC_SECRETS_FILE}" | cut -d= -f2-)"
  KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-${_kc_user}}"
  KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-${_kc_pass}}"
  unset _kc_user _kc_pass
fi
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:?ERROR: set KEYCLOAK_ADMIN_PASSWORD or provide ${_KC_SECRETS_FILE}}"

ADMIN_USER="${ADMIN_USER:-admin1}"
DEV_USER="${DEV_USER:-dev1}"
VIEWER_USER="${VIEWER_USER:-viewer1}"
USERS_PASSWORD="${USERS_PASSWORD:-111}"

ADMIN_EMAIL="${ADMIN_EMAIL:-admin1@example.local}"
DEV_EMAIL="${DEV_EMAIL:-dev1@example.local}"
VIEWER_EMAIL="${VIEWER_EMAIL:-viewer1@example.local}"
ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-Admin}"
ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-One}"
DEV_FIRST_NAME="${DEV_FIRST_NAME:-Dev}"
DEV_LAST_NAME="${DEV_LAST_NAME:-One}"
VIEWER_FIRST_NAME="${VIEWER_FIRST_NAME:-Viewer}"
VIEWER_LAST_NAME="${VIEWER_LAST_NAME:-One}"

API_DEPLOYMENT="${API_DEPLOYMENT:-api-deploy}"
FRONTEND_DEPLOYMENT="${FRONTEND_DEPLOYMENT:-frontend-deploy}"
KEYCLOAK_DEPLOYMENT="${KEYCLOAK_DEPLOYMENT:-keycloak}"
POSTGRES_STS="${POSTGRES_STS:-postgres-db}"
JENKINS_STS="${JENKINS_STS:-jenkins}"
JENKINS_SERVICE="${JENKINS_SERVICE:-jenkins}"

POSTGRES_SECRET_NAME="${POSTGRES_SECRET_NAME:-postgres-secret}"
POSTGRES_POD="${POSTGRES_POD:-postgres-db-0}"

# ------------------------------- Internals ---------------------------------- #
KEYCLOAK_URL="${KEYCLOAK_URL%/}"
API_URL="${API_URL%/}"
FRONTEND_URL="${FRONTEND_URL%/}"
JENKINS_URL="${JENKINS_URL%/}"

JENKINS_REDIRECT_URI="${JENKINS_REDIRECT_URI:-${JENKINS_URL}/securityRealm/finishLogin}"
JENKINS_POST_LOGOUT_URI="${JENKINS_POST_LOGOUT_URI:-${JENKINS_URL}/OicLogout}"
JENKINS_WEB_ORIGIN="${JENKINS_WEB_ORIGIN:-${JENKINS_URL}}"

# Use self-signed CA for Keycloak TLS if available; otherwise fall back to insecure
if [[ -f "${KEYCLOAK_CA_CERT:-}" ]]; then
  export CURL_CA_BUNDLE="${KEYCLOAK_CA_CERT}"
else
  # shellcheck disable=SC2034
  CURL_INSECURE="-k"
fi

TMP_DIR="$(mktemp -d)"
REQ_BODY="${TMP_DIR}/response.json"
REQ_HEADERS="${TMP_DIR}/headers.txt"
trap 'rm -rf "${TMP_DIR}"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

log()  { printf '[INFO] %s\n' "$*" >&2; }
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
    ${CURL_INSECURE:+-k}
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
  body="$(curl -sS ${CURL_INSECURE:+-k} -X POST \
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
  body="$(curl -sS ${CURL_INSECURE:+-k} -X POST \
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

# Returns the internal UUID of the client via stdout
ensure_client() {
  local clients_json client_internal_id
  clients_json="$(curl -sS ${CURL_INSECURE:+-k} -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}")"
  client_internal_id="$(jq -r '.[0].id // empty' <<<"${clients_json}")"

  if [[ -z "${client_internal_id}" ]]; then
    local payload code
    payload="$(printf '%s' '{
  "clientId": "'"${CLIENT_ID}"'",
  "name": "'"${CLIENT_ID}"'",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": true,
  "directAccessGrantsEnabled": true,
  "standardFlowEnabled": true,
  "serviceAccountsEnabled": false,
  "redirectUris": ["*"],
  "webOrigins": ["*"]
}')"
    code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" "${payload}" "${KC_ADMIN_TOKEN}")"
    [[ "${code}" == "201" ]] || die "Failed to create client '${CLIENT_ID}' (HTTP ${code})"
    log "Client '${CLIENT_ID}' created"

    clients_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}")"
    client_internal_id="$(jq -r '.[0].id // empty' <<<"${clients_json}")"
    [[ -n "${client_internal_id}" ]] || die "Client '${CLIENT_ID}' created but internal ID not found"
  fi

  local client_repr patched_repr code
  client_repr="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_internal_id}")"
  patched_repr="$(jq \
    '.enabled=true
    | .publicClient=true
    | .directAccessGrantsEnabled=true
    | .standardFlowEnabled=true
    | .serviceAccountsEnabled=false
    | .redirectUris=["*"]
    | .webOrigins=["*"]' <<<"${client_repr}")"
  code="$(request PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_internal_id}" "${patched_repr}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to update client '${CLIENT_ID}' configuration (HTTP ${code})"
  log "Client '${CLIENT_ID}' is configured for direct grants"

  echo "${client_internal_id}"
}

# ensure_mapper CLIENT_UUID MAPPER_NAME MAPPER_JSON
ensure_mapper() {
  local client_uuid="$1"
  local mapper_name="$2"
  local mapper_json="$3"

  local existing_id
  existing_id="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
    | jq -r --arg name "${mapper_name}" '.[] | select(.name==$name) | .id // empty')"

  if [[ -n "${existing_id}" ]]; then
    log "Mapper '${mapper_name}' already exists (id=${existing_id})"
    return
  fi

  local code
  code="$(request POST \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
    "${mapper_json}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "201" ]] || die "Failed to create mapper '${mapper_name}' (HTTP ${code})"
  log "Mapper '${mapper_name}' created"
}

# ensure_client_mappers CLIENT_UUID
# Adds: groups claim (realm roles) + audience claim (aud=task-manager-api)
ensure_client_mappers() {
  local client_uuid="$1"

  local groups_mapper
  groups_mapper="$(printf '%s' '{
  "name": "realm-roles-groups",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-realm-role-mapper",
  "consentRequired": false,
  "config": {
    "multivalued": "true",
    "userinfo.token.claim": "true",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "claim.name": "groups",
    "jsonType.label": "String"
  }
}')"
  ensure_mapper "${client_uuid}" "realm-roles-groups" "${groups_mapper}"

  local audience_mapper
  audience_mapper="$(printf '%s' '{
  "name": "audience-mapper",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-audience-mapper",
  "consentRequired": false,
  "config": {
    "included.client.audience": "'"${CLIENT_ID}"'",
    "id.token.claim": "false",
    "access.token.claim": "true"
  }
}')"
  ensure_mapper "${client_uuid}" "audience-mapper" "${audience_mapper}"
}

ensure_jenkins_client() {
  local clients_json client_internal_id
  clients_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${JENKINS_CLIENT_ID}")"
  client_internal_id="$(jq -r '.[0].id // empty' <<<"${clients_json}")"

  if [[ -z "${client_internal_id}" ]]; then
    local payload code
    payload="$(printf '%s' '{
  "clientId": "'"${JENKINS_CLIENT_ID}"'",
  "name": "'"${JENKINS_CLIENT_ID}"'",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "directAccessGrantsEnabled": false,
  "standardFlowEnabled": true,
  "serviceAccountsEnabled": false,
  "redirectUris": ["'"${JENKINS_REDIRECT_URI}"'"],
  "webOrigins": ["'"${JENKINS_WEB_ORIGIN}"'"],
  "attributes": {
    "post.logout.redirect.uris": "'"${JENKINS_POST_LOGOUT_URI}"'"
  }
}')"
    code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" "${payload}" "${KC_ADMIN_TOKEN}")"
    [[ "${code}" == "201" ]] || die "Failed to create client '${JENKINS_CLIENT_ID}' (HTTP ${code})"
    log "Client '${JENKINS_CLIENT_ID}' created"

    clients_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${JENKINS_CLIENT_ID}")"
    client_internal_id="$(jq -r '.[0].id // empty' <<<"${clients_json}")"
    [[ -n "${client_internal_id}" ]] || die "Client '${JENKINS_CLIENT_ID}' created but internal ID not found"
  fi

  local client_repr patched_repr code
  client_repr="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_internal_id}")"
  # Принимаем и http и https — Jenkins может отправлять любой протокол
  # в зависимости от того, как настроен reverse proxy
  local jenkins_host="${SERVER_IP}"
  patched_repr="$(jq \
    --arg redirect_https "https://jenkins.${jenkins_host}.nip.io/securityRealm/finishLogin" \
    --arg redirect_http  "http://jenkins.${jenkins_host}.nip.io/securityRealm/finishLogin" \
    --arg post_logout    "https://jenkins.${jenkins_host}.nip.io/OicLogout##http://jenkins.${jenkins_host}.nip.io/OicLogout" \
    --arg web_https      "https://jenkins.${jenkins_host}.nip.io" \
    --arg web_http       "http://jenkins.${jenkins_host}.nip.io" \
    '.enabled=true
    | .publicClient=false
    | .directAccessGrantsEnabled=false
    | .standardFlowEnabled=true
    | .serviceAccountsEnabled=false
    | .redirectUris=[$redirect_https, $redirect_http]
    | .webOrigins=[$web_https, $web_http]
    | .attributes["post.logout.redirect.uris"]=$post_logout' <<<"${client_repr}")"
  code="$(request PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_internal_id}" "${patched_repr}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to update client '${JENKINS_CLIENT_ID}' configuration (HTTP ${code})"
  log "Client '${JENKINS_CLIENT_ID}' is configured for Jenkins OIDC"
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
  local first_name="$4"
  local last_name="$5"

  local users_json user_id
  users_json="$(curl -sS -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}&exact=true")"
  user_id="$(jq -r '.[0].id // empty' <<<"${users_json}")"

  if [[ -z "${user_id}" ]]; then
    local payload code
    payload="$(printf '%s' '{
  "username": "'"${username}"'",
  "email": "'"${email}"'",
  "firstName": "'"${first_name}"'",
  "lastName": "'"${last_name}"'",
  "enabled": true,
  "emailVerified": true,
  "requiredActions": []
}')"
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

  local user_update_payload code
  user_update_payload="$(printf '%s' '{
  "username": "'"${username}"'",
  "email": "'"${email}"'",
  "firstName": "'"${first_name}"'",
  "lastName": "'"${last_name}"'",
  "enabled": true,
  "emailVerified": true,
  "requiredActions": []
}')"
  code="$(request PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}" "${user_update_payload}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to update profile for '${username}' (HTTP ${code})"

  local pass_payload
  pass_payload="$(printf '%s' '{
  "type": "password",
  "value": "'"${USERS_PASSWORD}"'",
  "temporary": false
}')"
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
  local namespace="${2:-${NAMESPACE}}"
  if kubectl -n "${namespace}" rollout status "${kind_name}" --timeout=180s >/dev/null; then
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
  local namespace="${2:-${NAMESPACE}}"
  local endpoints
  endpoints="$(kubectl -n "${namespace}" get endpoints "${svc}" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true)"
  if [[ -n "${endpoints}" ]]; then
    pass "Endpoints present for ${svc}: ${endpoints}"
  else
    fail "No endpoints for service ${svc}"
  fi
}

test_jenkins_oidc_redirect() {
  local code location
  : > "${REQ_HEADERS}"
  code="$(curl -sS -D "${REQ_HEADERS}" -o "${REQ_BODY}" -w "%{http_code}" \
    "${JENKINS_URL}/securityRealm/commenceLogin?from=%2F" || true)"

  if [[ "${code}" != "302" && "${code}" != "303" ]]; then
    fail "Jenkins OIDC commenceLogin -> expected 302/303, got ${code}"
    return
  fi

  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/{sub(/\r$/,"",$2); print $2; exit}' "${REQ_HEADERS}")"
  if [[ -z "${location}" ]]; then
    fail "Jenkins OIDC commenceLogin -> missing Location header"
    return
  fi

  if [[ "${location}" == *"/realms/${REALM}/protocol/openid-connect/auth"* ]]; then
    pass "Jenkins OIDC redirect to Keycloak auth endpoint"
  else
    fail "Jenkins OIDC redirect unexpected location: ${location}"
  fi
}

test_keycloak_auth_request_for_jenkins() {
  local encoded_redirect code
  encoded_redirect="$(jq -rn --arg v "${JENKINS_REDIRECT_URI}" '$v|@uri')"
  code="$(curl -sS -o "${REQ_BODY}" -w "%{http_code}" \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=${JENKINS_CLIENT_ID}&redirect_uri=${encoded_redirect}&response_type=code&scope=openid&state=smoke&nonce=smoke" || true)"

  if grep -qi "Invalid parameter: redirect_uri" "${REQ_BODY}"; then
    fail "Keycloak auth request for Jenkins client -> invalid redirect_uri"
    return
  fi

  if [[ "${code}" == "200" || "${code}" == "302" ]]; then
    pass "Keycloak auth request for Jenkins client is valid"
  else
    fail "Keycloak auth request for Jenkins client -> unexpected HTTP ${code}"
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

# --------------- Kubernetes RBAC helpers ------------------------------------ #

# Detect whether we are running inside a pod (in-cluster) or outside.
# Inside: use the pod's service account token and CA.
# Outside: rely on the default kubeconfig (already set up on the node/VPS).
K8S_RBAC_OPTS=()
if [[ -f /var/run/secrets/kubernetes.io/serviceaccount/ca.crt ]]; then
  K8S_RBAC_OPTS=(
    "--server=https://kubernetes.default.svc"
    "--certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  )
  log "Running inside pod — using in-cluster k8s API"
else
  log "Running outside pod — using default kubeconfig for k8s API"
fi

# test_clusterrole_exists NAME
test_clusterrole_exists() {
  local name="$1"
  if kubectl get clusterrole "${name}" >/dev/null 2>&1; then
    pass "ClusterRole '${name}' exists"
  else
    fail "ClusterRole '${name}' not found"
  fi
}

# test_clusterrolebinding_exists NAME
test_clusterrolebinding_exists() {
  local name="$1"
  if kubectl get clusterrolebinding "${name}" >/dev/null 2>&1; then
    pass "ClusterRoleBinding '${name}' exists"
  else
    fail "ClusterRoleBinding '${name}' not found"
  fi
}

# test_rolebinding_exists NAME NAMESPACE
test_rolebinding_exists() {
  local name="$1"
  local ns="$2"
  if kubectl -n "${ns}" get rolebinding "${name}" >/dev/null 2>&1; then
    pass "RoleBinding '${name}' in ns '${ns}' exists"
  else
    fail "RoleBinding '${name}' in ns '${ns}' not found"
  fi
}

# test_k8s_rbac DESCRIPTION TOKEN EXPECTED_YES_NO VERB RESOURCE [NAMESPACE]
# EXPECTED_YES_NO: "yes" or "no"
# If NAMESPACE is provided, tests namespace-scoped access; otherwise cluster-scoped.
test_k8s_rbac() {
  local description="$1"
  local token="$2"
  local expected="$3"
  local verb="$4"
  local resource="$5"
  local ns="${6:-}"

  if [[ -z "${token}" ]]; then
    fail "${description} -> skipped (no token)"
    return
  fi

  local can_i_args=("auth" "can-i" "${verb}" "${resource}")
  if [[ -n "${ns}" ]]; then
    can_i_args+=("-n" "${ns}")
  fi

  local result
  result="$(KUBECONFIG=/dev/null kubectl "${K8S_RBAC_OPTS[@]}" \
    --token="${token}" "${can_i_args[@]}" 2>/dev/null || true)"
  result="${result%%$'\n'*}"  # first line only
  result="${result// /}"       # trim spaces

  if [[ "${result}" == "${expected}" ]]; then
    pass "${description} -> can-i ${verb} ${resource}${ns:+ -n ${ns}} = ${expected}"
  else
    fail "${description} -> can-i ${verb} ${resource}${ns:+ -n ${ns}}: expected '${expected}', got '${result}'"
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
log "Jenkins URL: ${JENKINS_URL}"

log "Waiting for core workloads..."
test_rollout "deployment/${KEYCLOAK_DEPLOYMENT}"
test_rollout "deployment/${API_DEPLOYMENT}"
test_rollout "deployment/${FRONTEND_DEPLOYMENT}"
test_rollout "statefulset/${POSTGRES_STS}"
test_rollout "statefulset/${JENKINS_STS}" "${JENKINS_NAMESPACE}"

log "Bootstrapping Keycloak..."
KC_ADMIN_TOKEN="$(get_admin_token)"
[[ -n "${KC_ADMIN_TOKEN}" ]] || die "Cannot obtain Keycloak admin token. Check KEYCLOAK_URL/admin credentials."

ensure_realm
CLIENT_UUID="$(ensure_client)"
log "Client UUID: ${CLIENT_UUID}"
ensure_client_mappers "${CLIENT_UUID}"
ensure_jenkins_client
ensure_role "admin"
ensure_role "developer"
ensure_role "viewer"
ensure_user_with_role "${ADMIN_USER}" "${ADMIN_EMAIL}" "admin" "${ADMIN_FIRST_NAME}" "${ADMIN_LAST_NAME}"
ensure_user_with_role "${DEV_USER}" "${DEV_EMAIL}" "developer" "${DEV_FIRST_NAME}" "${DEV_LAST_NAME}"
ensure_user_with_role "${VIEWER_USER}" "${VIEWER_EMAIL}" "viewer" "${VIEWER_FIRST_NAME}" "${VIEWER_LAST_NAME}"

log "Running service-level checks..."
test_service_endpoints "postgres-svc"
test_service_endpoints "keycloak-svc"
test_service_endpoints "api-svc"
test_service_endpoints "frontend-svc"
test_service_endpoints "${JENKINS_SERVICE}" "${JENKINS_NAMESPACE}"
test_postgres_query

log "Running HTTP checks..."
test_http_code "Frontend root" "200" "${FRONTEND_URL}/"
test_http_code "API health" "200" "${API_URL}/health"
test_http_code "Keycloak OIDC discovery" "200" "${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration"
test_http_code "Jenkins login page" "200" "${JENKINS_URL}/login"
test_jenkins_oidc_redirect
test_keycloak_auth_request_for_jenkins

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

log "Running API RBAC tests..."
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

# ====================== Kubernetes RBAC Tests ================================
log "Running Kubernetes RBAC tests..."

log "  Checking RBAC resources exist..."
test_clusterrole_exists "diploma:admin"
test_clusterrole_exists "diploma:developer"
test_clusterrole_exists "diploma:viewer"
test_clusterrolebinding_exists "diploma:admin-cluster"
test_rolebinding_exists "diploma:admin-task-manager-api" "${NAMESPACE}"
test_rolebinding_exists "diploma:admin-cicd" "${JENKINS_NAMESPACE}"
test_rolebinding_exists "diploma:developer-task-manager-api" "${NAMESPACE}"
test_rolebinding_exists "diploma:viewer-task-manager-api" "${NAMESPACE}"

log "  Testing admin OIDC token k8s access (oidc:admin -> diploma:admin)..."
# admin can get nodes (cluster-wide, diploma:admin ClusterRole)
test_k8s_rbac "admin: get nodes" "${ADMIN_TOKEN}" "yes" "get" "nodes"
# admin can list namespaces (cluster-wide)
test_k8s_rbac "admin: list namespaces" "${ADMIN_TOKEN}" "yes" "list" "namespaces"
# admin can get pods in task-manager-api (via built-in admin RoleBinding)
test_k8s_rbac "admin: get pods in ${NAMESPACE}" "${ADMIN_TOKEN}" "yes" "get" "pods" "${NAMESPACE}"
# admin can get secrets in task-manager-api
test_k8s_rbac "admin: get secrets in ${NAMESPACE}" "${ADMIN_TOKEN}" "yes" "get" "secrets" "${NAMESPACE}"
# admin can delete pods in task-manager-api
test_k8s_rbac "admin: delete pods in ${NAMESPACE}" "${ADMIN_TOKEN}" "yes" "delete" "pods" "${NAMESPACE}"
# admin can get pods in cicd (via built-in admin RoleBinding)
test_k8s_rbac "admin: get pods in ${JENKINS_NAMESPACE}" "${ADMIN_TOKEN}" "yes" "get" "pods" "${JENKINS_NAMESPACE}"

log "  Testing developer OIDC token k8s access (oidc:developer -> diploma:developer)..."
# developer CANNOT get nodes (cluster-wide — no ClusterRoleBinding to admin)
test_k8s_rbac "developer: get nodes (denied)" "${DEV_TOKEN}" "no" "get" "nodes"
# developer CAN get pods in task-manager-api (diploma:developer allows it)
test_k8s_rbac "developer: get pods in ${NAMESPACE}" "${DEV_TOKEN}" "yes" "get" "pods" "${NAMESPACE}"
# developer CAN create deployments in task-manager-api
test_k8s_rbac "developer: create deployments in ${NAMESPACE}" "${DEV_TOKEN}" "yes" "create" "deployments" "${NAMESPACE}"
# developer CANNOT get secrets in task-manager-api (diploma:developer excludes secrets)
test_k8s_rbac "developer: get secrets in ${NAMESPACE} (denied)" "${DEV_TOKEN}" "no" "get" "secrets" "${NAMESPACE}"
# developer CANNOT delete pods in task-manager-api (diploma:developer excludes delete)
test_k8s_rbac "developer: delete pods in ${NAMESPACE} (denied)" "${DEV_TOKEN}" "no" "delete" "pods" "${NAMESPACE}"

log "  Testing viewer OIDC token k8s access (oidc:viewer -> diploma:viewer)..."
# viewer CANNOT get nodes (cluster-wide)
test_k8s_rbac "viewer: get nodes (denied)" "${VIEWER_TOKEN}" "no" "get" "nodes"
# viewer CAN get pods in task-manager-api (diploma:viewer allows read-only)
test_k8s_rbac "viewer: get pods in ${NAMESPACE}" "${VIEWER_TOKEN}" "yes" "get" "pods" "${NAMESPACE}"
# viewer CANNOT create deployments in task-manager-api (read-only)
test_k8s_rbac "viewer: create deployments in ${NAMESPACE} (denied)" "${VIEWER_TOKEN}" "no" "create" "deployments" "${NAMESPACE}"
# viewer CANNOT get secrets in task-manager-api (diploma:viewer excludes secrets)
test_k8s_rbac "viewer: get secrets in ${NAMESPACE} (denied)" "${VIEWER_TOKEN}" "no" "get" "secrets" "${NAMESPACE}"

echo
echo "==================== RESULT ===================="
echo "Passed: ${PASS_COUNT}"
echo "Failed: ${FAIL_COUNT}"
echo "================================================"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi

````

