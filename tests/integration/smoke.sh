#!/usr/bin/env bash
# Smoke test across repositories: starts the backend from components/backend with its production config against a
# local Postgres, checks /health, then builds `al` from components/cli and takes it as far as it goes without the app.
# The client API calls the app would make (account, Assistant, Link, pairing code) are made with curl.
#
# Needs: the components cloned (`mise run clone`), Erlang/Elixir and Rust (`mise install`), curl, jq, and a Postgres
# that DATABASE_URL can reach and create a database on.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
components="$root/components"
port="${SMOKE_PORT:-4100}"
service="http://localhost:$port"
export DATABASE_URL="${DATABASE_URL:-ecto://postgres:postgres@localhost:5432/assistant_link_smoke}"

work="$(mktemp -d)"
server_pid=""
wait_pid=""
cleanup() {
  [[ -n "$wait_pid" ]] && kill "$wait_pid" 2>/dev/null || true
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

step() { printf '\n==> %s\n' "$*"; }
fail() {
  echo "FAIL: $*" >&2
  if [[ -f "$work/server.log" ]]; then
    echo "--- last lines of the server log ---" >&2
    tail -n 40 "$work/server.log" >&2
  fi
  exit 1
}

# Polls `$1` (a command) once a second until it succeeds, for up to $2 seconds.
eventually() {
  local deadline=$((SECONDS + $2))
  until eval "$1"; do
    ((SECONDS < deadline)) || return 1
    sleep 1
  done
}

for repo in backend cli; do
  [[ -d "$components/$repo/.git" ]] || fail "components/$repo/ is missing; run scripts/clone first"
done

# The backend runs as in production (MIX_ENV=prod, config/runtime.exs), configured the way a self-hosted service on
# plain HTTP would be.
export MIX_ENV=prod
export PHX_SERVER=true
export PORT="$port"
export PHX_HOST=localhost
export PHX_SCHEME=http
export PHX_URL_PORT="$port"
export DATABASE_SSL=false
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-smoke-test-secret-key-base-smoke-test-secret-key-base-smoke-test}"

step "backend: build and migrate"
(
  cd "$components/backend"
  mix deps.get --only prod
  mix compile
  mix ecto.create
  mix ecto.migrate
)

step "backend: start on $service"
(cd "$components/backend" && exec mix phx.server) >"$work/server.log" 2>&1 &
server_pid=$!

step "backend: GET /health"
eventually 'curl -fsS "$service/health" >"$work/health.json" 2>/dev/null' 90 || fail "/health did not respond"
[[ "$(jq -r .status "$work/health.json")" == "ok" ]] || fail "/health returned $(cat "$work/health.json")"
echo "health: $(cat "$work/health.json")"

step "cli: build al"
(cd "$components/cli" && cargo build --quiet)
al="$components/cli/target/debug/al"
"$al" --version

# The app's side of pairing, through the client API.
api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-fsS -X "$method" "$service/api/v1$path" -H 'content-type: application/json')
  [[ -n "${credential:-}" ]] && args+=(-H "authorization: Bearer $credential")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

step "app API: account, Assistant, Link, pairing code"
credential="$(api POST /accounts | jq -r .credential)"
[[ "$credential" == ala_* ]] || fail "no account credential"
assistant_id="$(api POST /assistants '{"name": "Smoke", "avatar": "avatar-1"}' | jq -r .assistant.id)"
link_id="$(api POST "/assistants/$assistant_id/links" | jq -r .link.id)"
api POST "/links/$link_id/pairing_code" >"$work/pairing.json"
code="$(jq -r .code "$work/pairing.json")"
jq -r .pairing_text "$work/pairing.json"
grep -qF "Service: $service" <(jq -r .pairing_text "$work/pairing.json") || fail "pairing text does not name $service"

link_status() {
  api GET /assistants | jq -r --arg id "$link_id" '.assistants[].links[] | select(.id == $id) | .status'
}
[[ "$(link_status)" == "not_paired" ]] || fail "new Link is not not_paired"

export AL_SERVER="$service"
export XDG_CONFIG_HOME="$work/config"

step "al pair"
"$al" pair "$code" | tee "$work/pair.json"
[[ "$(jq -r .assistant_name "$work/pair.json")" == "Smoke" ]] || fail "al pair did not report the Assistant"
[[ "$(jq -r .link_id "$work/pair.json")" == "$link_id" ]] || fail "al pair paired another Link"

step "al status"
"$al" status | tee "$work/status.json"
[[ "$(jq -r .check "$work/status.json")" == "accepted" ]] || fail "al status was not accepted"

step "al wait: the Link goes online, then offline"
"$al" wait >"$work/events.log" 2>"$work/wait.log" &
wait_pid=$!
eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online during al wait"
echo "online while al wait runs"
kill -INT "$wait_pid"
wait "$wait_pid" || fail "al wait exited $? on SIGINT"
wait_pid=""
eventually '[[ "$(link_status)" == "offline" ]]' 15 || fail "Link did not go offline after al wait stopped"
echo "offline after al wait stopped"

step "install.md"
curl -fsS "$service/install.md" | grep -qF "https://github.com/assistant-link/cli" || fail "install.md does not point at assistant-link/cli"
echo "served, installs al from assistant-link/cli"

printf '\nSmoke test passed.\n'
