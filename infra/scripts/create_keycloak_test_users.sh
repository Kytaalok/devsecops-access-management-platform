#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Create a reproducible Keycloak test population for scalability checks.
# Default: 100 users in realm devsecops:
#   - loaduser001..loaduser010 -> admin
#   - loaduser011..loaduser055 -> developer
#   - loaduser056..loaduser100 -> viewer
###############################################################################

NAMESPACE="${NAMESPACE:-task-manager-api}"
SERVER_IP="${SERVER_IP:-83.69.249.206}"
KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.${SERVER_IP}.nip.io}"
KEYCLOAK_CA_CERT="${KEYCLOAK_CA_CERT:-/etc/rancher/k3s/keycloak-ca.crt}"
REALM="${REALM:-devsecops}"

USER_PREFIX="${USER_PREFIX:-loaduser}"
USER_COUNT="${USER_COUNT:-100}"
ADMIN_COUNT="${ADMIN_COUNT:-10}"
DEVELOPER_COUNT="${DEVELOPER_COUNT:-45}"
USER_EMAIL_DOMAIN="${USER_EMAIL_DOMAIN:-example.local}"
USERS_PASSWORD="${USERS_PASSWORD:-111}"
DRY_RUN="${DRY_RUN:-false}"

_KC_SECRETS_FILE="${KC_SECRETS_FILE:-infra/k3s/jenkins/secrets/jenkins-admin.env}"
if [[ -f "${_KC_SECRETS_FILE}" ]]; then
  _kc_user="$(grep '^jenkins-admin-user=' "${_KC_SECRETS_FILE}" | cut -d= -f2-)"
  _kc_pass="$(grep '^jenkins-admin-password=' "${_KC_SECRETS_FILE}" | cut -d= -f2-)"
  KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-${_kc_user}}"
  KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-${_kc_pass}}"
  unset _kc_user _kc_pass
fi
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:?ERROR: set KEYCLOAK_ADMIN_PASSWORD or provide ${_KC_SECRETS_FILE}}"

KEYCLOAK_URL="${KEYCLOAK_URL%/}"
TMP_DIR="$(mktemp -d)"
REQ_BODY="${TMP_DIR}/response.json"
trap 'rm -rf "${TMP_DIR}"' EXIT

CURL_INSECURE=""
if [[ -f "${KEYCLOAK_CA_CERT:-}" ]]; then
  export CURL_CA_BUNDLE="${KEYCLOAK_CA_CERT}"
else
  CURL_INSECURE="-k"
fi

log() { printf '[INFO] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

request() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  local token="${4:-}"
  local content_type="${5:-application/json}"
  local args=(-sS ${CURL_INSECURE:+-k} -o "${REQ_BODY}" -w "%{http_code}" -X "${method}" "${url}")

  if [[ -n "${token}" ]]; then
    args+=(-H "Authorization: Bearer ${token}")
  fi
  if [[ -n "${data}" ]]; then
    args+=(-H "Content-Type: ${content_type}" --data "${data}")
  fi

  curl "${args[@]}" || true
}

get_admin_token() {
  curl -sS ${CURL_INSECURE:+-k} \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=admin-cli" \
    --data-urlencode "username=${KEYCLOAK_ADMIN_USER}" \
    --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    | jq -r '.access_token // empty'
}

ensure_role() {
  local role="$1"
  local code
  code="$(request GET "${KEYCLOAK_URL}/admin/realms/${REALM}/roles/${role}" "" "${KC_ADMIN_TOKEN}")"
  if [[ "${code}" == "200" ]]; then
    return 0
  fi
  [[ "${code}" == "404" ]] || die "Unexpected response while checking role '${role}': HTTP ${code}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY_RUN: would create role '${role}'"
    return 0
  fi
  code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/roles" "{\"name\":\"${role}\"}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "201" ]] || die "Failed to create role '${role}' (HTTP ${code})"
  log "Role '${role}' created"
}

role_for_index() {
  local i="$1"
  if (( i <= ADMIN_COUNT )); then
    printf 'admin'
  elif (( i <= ADMIN_COUNT + DEVELOPER_COUNT )); then
    printf 'developer'
  else
    printf 'viewer'
  fi
}

ensure_user_with_role() {
  local index="$1"
  local role="$2"
  local username email first_name last_name users_json user_id payload code role_json

  username="$(printf '%s%03d' "${USER_PREFIX}" "${index}")"
  email="${username}@${USER_EMAIL_DOMAIN}"
  first_name="Load"
  last_name="User$(printf '%03d' "${index}")"

  users_json="$(curl -sS ${CURL_INSECURE:+-k} -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}&exact=true")"
  user_id="$(jq -r '.[0].id // empty' <<<"${users_json}")"

  payload="$(jq -n \
    --arg username "${username}" \
    --arg email "${email}" \
    --arg firstName "${first_name}" \
    --arg lastName "${last_name}" \
    '{username:$username,email:$email,firstName:$firstName,lastName:$lastName,enabled:true,emailVerified:true,requiredActions:[]}')"

  if [[ -z "${user_id}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "DRY_RUN: would create ${username} with role ${role}"
      return 0
    fi
    code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" "${payload}" "${KC_ADMIN_TOKEN}")"
    [[ "${code}" == "201" ]] || die "Failed to create user '${username}' (HTTP ${code})"
    users_json="$(curl -sS ${CURL_INSECURE:+-k} -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}&exact=true")"
    user_id="$(jq -r '.[0].id // empty' <<<"${users_json}")"
    [[ -n "${user_id}" ]] || die "User '${username}' created but ID not found"
    log "Created ${username}"
  else
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "DRY_RUN: would update ${username} with role ${role}"
      return 0
    fi
    code="$(request PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}" "${payload}" "${KC_ADMIN_TOKEN}")"
    [[ "${code}" == "204" ]] || die "Failed to update user '${username}' (HTTP ${code})"
  fi

  local pass_payload
  pass_payload="$(jq -n --arg password "${USERS_PASSWORD}" '{type:"password",value:$password,temporary:false}')"
  code="$(request PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}/reset-password" "${pass_payload}" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to set password for '${username}' (HTTP ${code})"

  role_json="$(curl -sS ${CURL_INSECURE:+-k} -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/roles/${role}")"
  [[ "$(jq -r '.name // empty' <<<"${role_json}")" == "${role}" ]] || die "Failed to fetch role '${role}'"
  code="$(request POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}/role-mappings/realm" "[${role_json}]" "${KC_ADMIN_TOKEN}")"
  [[ "${code}" == "204" ]] || die "Failed to assign role '${role}' to '${username}' (HTTP ${code})"

  log "Configured ${username} -> ${role}"
}

main() {
  require_cmd curl
  require_cmd jq

  [[ "${USER_COUNT}" =~ ^[0-9]+$ ]] || die "USER_COUNT must be an integer"
  [[ "${ADMIN_COUNT}" =~ ^[0-9]+$ ]] || die "ADMIN_COUNT must be an integer"
  [[ "${DEVELOPER_COUNT}" =~ ^[0-9]+$ ]] || die "DEVELOPER_COUNT must be an integer"
  (( USER_COUNT > 0 )) || die "USER_COUNT must be greater than zero"
  (( ADMIN_COUNT + DEVELOPER_COUNT <= USER_COUNT )) || die "ADMIN_COUNT + DEVELOPER_COUNT must be <= USER_COUNT"

  log "Keycloak URL: ${KEYCLOAK_URL}"
  log "Realm: ${REALM}"
  log "Target users: ${USER_COUNT} (${ADMIN_COUNT} admin, ${DEVELOPER_COUNT} developer, $((USER_COUNT - ADMIN_COUNT - DEVELOPER_COUNT)) viewer)"

  KC_ADMIN_TOKEN="$(get_admin_token)"
  [[ -n "${KC_ADMIN_TOKEN}" ]] || die "Cannot obtain Keycloak admin token"

  ensure_role admin
  ensure_role developer
  ensure_role viewer

  local i role
  for i in $(seq 1 "${USER_COUNT}"); do
    role="$(role_for_index "${i}")"
    ensure_user_with_role "${i}" "${role}"
  done

  log "Done. Managed users with prefix '${USER_PREFIX}': ${USER_COUNT}"
}

main "$@"
