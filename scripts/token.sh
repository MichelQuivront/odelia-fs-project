#!/usr/bin/env bash
# Fetches a Keycloak access token for a course account (password grant,
# public client "kanban-app") and prints it on stdout.
#
#   TOKEN=$(bash scripts/token.sh alice)
#   curl -H "Authorization: Bearer $TOKEN" http://localhost:9080/api/boards
#
# Accounts and passwords come from keycloak/kanban-realm.json:
#   alice/alice (user), bob/bob (user), carol/carol (user + admin).
#
# The token MUST be requested at http://localhost:8081: the backend expects
# iss=http://localhost:8081/realms/kanban (mp.jwt.verify.issuer), so a token
# minted at http://keycloak:8080 is rejected with 401.
#
# Overridable: KC_URL (default http://localhost:8081), PASSWORD.
set -euo pipefail

user=${1:-}
case "$user" in
  alice|bob|carol) ;;
  *) echo "usage: $0 alice|bob|carol" >&2; exit 64 ;;
esac

KC_URL=${KC_URL:-http://localhost:8081}
password=${PASSWORD:-$user}

response=$(curl -sS "$KC_URL/realms/kanban/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=kanban-app \
  -d "username=$user" -d "password=$password")

token=$(printf '%s' "$response" | jq -r '.access_token // empty')
if [[ -z "$token" ]]; then
  echo "Could not get a token for $user: $(printf '%s' "$response" | jq -c '{error, error_description}' 2>/dev/null || echo "$response")" >&2
  exit 1
fi
printf '%s\n' "$token"
