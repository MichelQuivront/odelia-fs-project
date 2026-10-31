#!/usr/bin/env bash
# End-to-end API checks for exercise 17 (board sharing), R2-R10 + admin bypass
# + immediate revocation. Needs curl + jq and a running stack (Keycloak,
# PostgreSQL, Liberty). Run from the HOST: tokens must be minted at
# localhost:8081 (see scripts/token.sh).
#
#   bash scripts/test-sharing.sh            # prints OK/KO per check
#   echo $?                                 # number of failed checks (0 = all green)
#
# Overridable: KC_URL (for token.sh), API_URL.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
API_URL=${API_URL:-http://localhost:9080/api}
BODY=$(mktemp)
FAILS=0
BID=""

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

# req TOKEN METHOD PATH [JSON] -> prints the HTTP status; the body is left in $BODY
req() {
  local args=(-s -o "$BODY" -w '%{http_code}' -X "$2" -H "Authorization: Bearer $1")
  if [[ $# -ge 4 ]]; then
    args+=(-H 'Content-Type: application/json' -d "$4")
  fi
  curl "${args[@]}" "$API_URL$3"
}

check() { # LABEL EXPECTED ACTUAL
  if [[ "$2" == "$3" ]]; then
    printf '  \033[32mOK\033[0m  %-66s %s\n' "$1" "$3"
  else
    printf '  \033[31mKO\033[0m  %-66s got %s, expected %s\n' "$1" "$3" "$2"
    FAILS=$((FAILS + 1))
  fi
}

# count_board TOKEN -> how many times $BID appears in GET /boards for that caller
count_board() {
  req "$1" GET /boards >/dev/null
  jq --argjson id "$BID" '[.[] | select(.id == $id)] | length' "$BODY"
}

ALICE=$(bash "$HERE/token.sh" alice) || exit 2
BOB=$(bash "$HERE/token.sh" bob) || exit 2
CAROL=$(bash "$HERE/token.sh" carol) || exit 2   # admin

# Best effort: never leave a test board behind, even when a check aborts the run.
# shellcheck disable=SC2317  # only reached through the EXIT trap
cleanup() {
  if [[ -n "$BID" ]]; then
    curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $ALICE" "$API_URL/boards/$BID"
  fi
  rm -f "$BODY"
}
trap cleanup EXIT

echo "Setup"
check "alice creates a board" 201 "$(req "$ALICE" POST /boards '{"name":"ex17-test"}')"
BID=$(jq -r .id "$BODY")
req "$ALICE" GET "/boards/$BID/lists" >/dev/null
L1=$(jq -r '.[0].id' "$BODY"); L2=$(jq -r '.[1].id' "$BODY")
check "alice adds a card to read later" 201 "$(req "$ALICE" POST "/lists/$L1/cards" '{"title":"alice card"}')"
ACARD=$(jq -r .id "$BODY")

echo "R9 - bob is a stranger before sharing"
check "bob GET board -> 403" 403 "$(req "$BOB" GET "/boards/$BID")"
check "bob GET columns -> 403" 403 "$(req "$BOB" GET "/boards/$BID/lists")"
check "bob GET members -> 403" 403 "$(req "$BOB" GET "/boards/$BID/members")"
check "bob GET a card -> 403" 403 "$(req "$BOB" GET "/cards/$ACARD")"
check "bob adds a card -> 403" 403 "$(req "$BOB" POST "/lists/$L1/cards" '{"title":"intrusion"}')"
check "bob's GET /boards does not include the board" 0 "$(count_board "$BOB")"

echo "R2 / R5 / R10 - adding members"
check "alice adds ' Bob ' -> 201" 201 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":" Bob "}')"
check "  stored username is normalized to 'bob'" bob "$(jq -r .username "$BODY")"
check "alice adds bob again -> 400 (duplicate)" 400 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"bob"}')"
check "alice adds 'ALICE' (herself, the owner) -> 400" 400 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"ALICE"}')"
check "alice adds a blank username -> 400" 400 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"  "}')"
check "alice adds carol -> 201" 201 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"carol"}')"

echo "R3 - listing members"
check "bob GET members -> 200" 200 "$(req "$BOB" GET "/boards/$BID/members")"
check "  members are bob,carol (owner not stored)" "bob,carol" "$(jq -r '[.[].username] | join(",")' "$BODY")"

echo "R6 - GET /boards"
check "bob's GET /boards includes the board exactly once" 1 "$(count_board "$BOB")"
check "alice's GET /boards includes it exactly once" 1 "$(count_board "$ALICE")"

echo "R7 - member works on cards and columns"
check "bob GET board -> 200" 200 "$(req "$BOB" GET "/boards/$BID")"
check "bob GET columns -> 200" 200 "$(req "$BOB" GET "/boards/$BID/lists")"
check "bob GET cards of a column -> 200" 200 "$(req "$BOB" GET "/lists/$L1/cards")"
check "bob GET alice's card -> 200" 200 "$(req "$BOB" GET "/cards/$ACARD")"
check "bob adds a card -> 201" 201 "$(req "$BOB" POST "/lists/$L1/cards" '{"title":"bob card"}')"
CID=$(jq -r .id "$BODY")
check "bob edits the card -> 200" 200 "$(req "$BOB" PUT "/cards/$CID" '{"title":"bob card v2"}')"
check "bob moves the card to another column -> 200" 200 "$(req "$BOB" PATCH "/cards/$CID/move" "{\"targetListId\":$L2,\"position\":0}")"
check "  card is now in that column" "$L2" "$(jq -r .listId "$BODY")"
check "bob adds a column -> 201" 201 "$(req "$BOB" POST "/boards/$BID/lists" '{"name":"Bob column","position":3}')"
COL=$(jq -r .id "$BODY")
check "bob renames the column -> 200" 200 "$(req "$BOB" PUT "/lists/$COL" '{"name":"Bob col 2","position":3}')"
check "bob deletes the card -> 204" 204 "$(req "$BOB" DELETE "/cards/$CID")"
check "bob deletes the column -> 204" 204 "$(req "$BOB" DELETE "/lists/$COL")"

echo "R8 - owner-only actions refused to a member (403, never 400/404/500)"
check "bob renames the board -> 403" 403 "$(req "$BOB" PUT "/boards/$BID" '{"name":"hacked"}')"
check "bob renames the board to a blank name -> 403" 403 "$(req "$BOB" PUT "/boards/$BID" '{"name":""}')"
check "bob deletes the board -> 403" 403 "$(req "$BOB" DELETE "/boards/$BID")"
check "bob adds dave -> 403" 403 "$(req "$BOB" POST "/boards/$BID/members" '{"username":"dave"}')"
check "bob adds a blank username -> 403" 403 "$(req "$BOB" POST "/boards/$BID/members" '{"username":""}')"
check "bob removes carol (another member) -> 403" 403 "$(req "$BOB" DELETE "/boards/$BID/members/carol")"
check "bob removes himself -> 403" 403 "$(req "$BOB" DELETE "/boards/$BID/members/bob")"
req "$ALICE" GET "/boards/$BID" >/dev/null
check "  board name is unchanged" ex17-test "$(jq -r .name "$BODY")"
req "$ALICE" GET "/boards/$BID/members" >/dev/null
check "  members are unchanged" "bob,carol" "$(jq -r '[.[].username] | join(",")' "$BODY")"

echo "Admin bypass (carol, after being removed as a member)"
check "alice removes carol -> 204" 204 "$(req "$ALICE" DELETE "/boards/$BID/members/carol")"
check "carol (admin) GET board -> 200" 200 "$(req "$CAROL" GET "/boards/$BID")"
check "carol (admin) renames the board -> 200" 200 "$(req "$CAROL" PUT "/boards/$BID" '{"name":"ex17-renamed"}')"
check "carol (admin) GET members -> 200" 200 "$(req "$CAROL" GET "/boards/$BID/members")"
check "carol (admin) adds dave -> 201" 201 "$(req "$CAROL" POST "/boards/$BID/members" '{"username":"dave"}')"
check "carol (admin) removes dave -> 204" 204 "$(req "$CAROL" DELETE "/boards/$BID/members/dave")"
check "alice renames her board to blank -> 400 (owner validated)" 400 "$(req "$ALICE" PUT "/boards/$BID" '{"name":""}')"

echo "R10 / R4 - removing, immediate revocation"
check "alice removes herself (owner) -> 400" 400 "$(req "$ALICE" DELETE "/boards/$BID/members/alice")"
check "alice removes 'BOB' -> 204" 204 "$(req "$ALICE" DELETE "/boards/$BID/members/BOB")"
check "bob's very next request is denied -> 403" 403 "$(req "$BOB" GET "/boards/$BID")"
check "bob can no longer add cards -> 403" 403 "$(req "$BOB" POST "/lists/$L1/cards" '{"title":"late"}')"
check "bob's GET /boards no longer includes the board" 0 "$(count_board "$BOB")"
check "alice removes bob again -> 404 (not a member)" 404 "$(req "$ALICE" DELETE "/boards/$BID/members/bob")"

echo "Cascade - deleting a board deletes its memberships"
check "alice re-adds bob -> 201" 201 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"bob"}')"
check "carol (admin) deletes the board -> 204" 204 "$(req "$CAROL" DELETE "/boards/$BID")"
check "  members of the deleted board -> 404" 404 "$(req "$ALICE" GET "/boards/$BID/members")"
check "  bob's GET /boards no longer includes it" 0 "$(count_board "$BOB")"
BID=""

echo
if [[ $FAILS -eq 0 ]]; then echo "All checks passed."; else echo "$FAILS check(s) failed."; fi
exit "$FAILS"
