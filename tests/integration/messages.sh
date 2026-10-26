# Text messages between the app and `al`. Sourced by smoke.sh once the backend is up; uses its helpers (api, step,
# fail, eventually, link_status, $al, $work). Every test creates its own account.

new_account() {
  credential=""
  api POST /accounts >"$work/account.json"
  credential="$(jq -r .credential "$work/account.json")"
  account_id="$(jq -r .account_id "$work/account.json")"
}

new_assistant() {
  api POST /assistants '{"name": "Test", "avatar": "avatar-1"}' | jq -r .assistant.id
}

# Creates a Link on the Assistant ($1) and pairs it into the key file ($2). Its id is in $link_id.
pair_link() {
  local code
  link_id="$(api POST "/assistants/$1/links" | jq -r .link.id)"
  code="$(api POST "/links/$link_id/pairing_code" | jq -r .code)"
  "$al" pair "$code" --key-file "$2" >/dev/null
}

uuid7() {
  local time random
  time="$(printf '%012x' "$(date +%s%3N)")"
  random="$(od -An -N9 -tx1 /dev/urandom | tr -d ' \n')"
  echo "${time:0:8}-${time:8:4}-7${random:0:3}-8${random:3:3}-${random:6:12}"
}

# The user sends text ($2) to the Assistant ($1). Prints the event id.
send() {
  api POST "/assistants/$1/messages" "$(jq -nc --arg text "$2" --arg key "$(uuid7)" '{text: $text, idempotency_key: $key}')" |
    jq -r .message.id
}

# Starts `al wait` with the key file ($1), stdout in $2; its pid is in $waiter.
start_wait() {
  : >"$2"
  AL_LINK_KEY="$(cat "$1")" "$al" wait >"$2" 2>"$2.err" &
  waiter=$!
  pids+=("$waiter")
}

stop_wait() {
  kill -INT "$1"
  wait "$1" || fail "al wait exited $? on SIGINT"
}

texts() { jq -r .text_message.text "$1" | paste -sd, -; }
delivery_status() { api GET "/assistants/$1/events" | jq -r --arg id "$2" '.events[] | select(.id == $id) | .delivery_status'; }
unread() { AL_LINK_KEY="$(cat "$1")" "$al" status | jq -r .unread_count; }

test_delivery() {
  step "5.1 a message from the app reaches al wait and is delivered"
  new_account
  local assistant key event
  assistant="$(new_assistant)"
  key="$work/delivery.key"
  pair_link "$assistant" "$key"
  start_wait "$key" "$work/delivery.out"
  eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online"
  event="$(send "$assistant" "Hi")"
  eventually '[[ -s "$work/delivery.out" ]]' 15 || fail "al wait printed nothing"
  jq -e --arg id "$event" '.id == $id and .type == "text_message" and .deleted == false and .text_message == {text: "Hi"}' \
    "$work/delivery.out" >/dev/null || fail "unexpected line: $(cat "$work/delivery.out")"
  eventually '[[ "$(delivery_status "$assistant" "$event")" == "delivered" ]]' 15 || fail "message was not delivered"
  stop_wait "$waiter"
}

test_catch_up() {
  step "5.2 messages sent before al wait arrive in order, once"
  new_account
  local assistant key
  assistant="$(new_assistant)"
  key="$work/catch-up.key"
  pair_link "$assistant" "$key" >/dev/null
  send "$assistant" "one" >/dev/null
  send "$assistant" "two" >/dev/null
  start_wait "$key" "$work/catch-up.out"
  eventually '[[ "$(wc -l <"$work/catch-up.out")" -eq 2 ]]' 15 || fail "al wait did not print both messages"
  [[ "$(texts "$work/catch-up.out")" == "one,two" ]] || fail "wrong order: $(texts "$work/catch-up.out")"
  eventually '[[ "$(unread "$key")" -eq 0 ]]' 15 || fail "messages were not acknowledged"
  stop_wait "$waiter"

  start_wait "$key" "$work/catch-up-again.out"
  send "$assistant" "three" >/dev/null
  eventually '[[ -s "$work/catch-up-again.out" ]]' 15 || fail "restarted al wait printed nothing"
  [[ "$(texts "$work/catch-up-again.out")" == "three" ]] || fail "repeat after restart: $(texts "$work/catch-up-again.out")"
  stop_wait "$waiter"
}

test_two_links() {
  step "5.3 every Link gets every message; a later Link nothing older"
  new_account
  local assistant
  assistant="$(new_assistant)"
  pair_link "$assistant" "$work/first.key" >/dev/null
  pair_link "$assistant" "$work/second.key" >/dev/null
  send "$assistant" "one" >/dev/null
  start_wait "$work/first.key" "$work/first.out"
  local first=$waiter
  start_wait "$work/second.key" "$work/second.out"
  local second=$waiter
  eventually '[[ -s "$work/first.out" && -s "$work/second.out" ]]' 15 || fail "a Link did not get the first message"

  pair_link "$assistant" "$work/third.key" >/dev/null
  start_wait "$work/third.key" "$work/third.out"
  local third=$waiter
  send "$assistant" "two" >/dev/null
  eventually '[[ -s "$work/third.out" ]]' 15 || fail "the later Link got nothing"
  eventually '[[ "$(texts "$work/first.out")" == "one,two" && "$(texts "$work/second.out")" == "one,two" ]]' 15 ||
    fail "the first Links got $(texts "$work/first.out") and $(texts "$work/second.out")"
  [[ "$(texts "$work/third.out")" == "two" ]] || fail "the later Link got $(texts "$work/third.out")"
  stop_wait "$first"
  stop_wait "$second"
  stop_wait "$third"
}

test_unread_stdout() {
  step "5.4 a message nobody reads from stdout stays unacknowledged"
  new_account
  local assistant key text last code=0
  assistant="$(new_assistant)"
  key="$work/unread.key"
  pair_link "$assistant" "$key" >/dev/null
  mkfifo "$work/unread.fifo"
  sleep 600 <"$work/unread.fifo" &
  local reader=$!
  pids+=("$reader")
  start_wait "$key" "$work/unread.fifo"
  eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online"
  text="$(head -c 4000 /dev/zero | tr '\0' x)"
  for _ in $(seq 40); do last="$(send "$assistant" "$text")"; done
  sleep 3
  [[ "$(link_status)" == "online" ]] || fail "Link went offline while the write was pending"
  [[ "$(unread "$key")" -gt 0 ]] || fail "every message was acknowledged"
  [[ "$(delivery_status "$assistant" "$last")" == "sent" ]] || fail "the last message was delivered"

  kill "$reader"
  wait "$waiter" || code=$?
  [[ "$code" -eq 1 ]] || fail "al wait exited $code after stdout closed"
  eventually '[[ "$(link_status)" == "offline" ]]' 15 || fail "Link did not go offline"
  [[ "$(unread "$key")" -gt 0 ]] || fail "the pending message was acknowledged"
}

test_send() {
  step "5.4 al send reaches the app"
  new_account
  local assistant key id code=0
  assistant="$(new_assistant)"
  key="$work/send.key"
  pair_link "$assistant" "$key" >/dev/null
  AL_LINK_KEY="$(cat "$key")" "$al" send "Your reminder is set." >"$work/send.json"
  id="$(jq -r .message_id "$work/send.json")"
  api GET "/assistants/$assistant/events" |
    jq -e --arg id "$id" '.events[] | select(.id == $id and .sender == "assistant" and .text_message.text == "Your reminder is set.")' \
      >/dev/null || fail "the app does not have the message"
  [[ "$(link_status)" == "offline" ]] || fail "al send changed the Link's presence"
  [[ "$(unread "$key")" -eq 0 ]] || fail "the Assistant's own message is deliverable"
  AL_LINK_KEY="$(cat "$key")" "$al" send "$(head -c 4001 /dev/zero | tr '\0' x)" >/dev/null || code=$?
  [[ "$code" -eq 4 ]] || fail "al send of 4,001 characters exited $code"
}

test_status() {
  step "5.6 no_paired_link until pairing; al status disturbs nothing"
  new_account
  local assistant key
  assistant="$(new_assistant)"
  key="$work/status.key"
  link_id="$(api POST "/assistants/$assistant/links" | jq -r .link.id)"
  curl -sS -X POST "$service/api/v1/assistants/$assistant/messages" -H "authorization: Bearer $credential" \
    -H 'content-type: application/json' -d "{\"text\": \"Hi\", \"idempotency_key\": \"$(uuid7)\"}" | jq -e '.error.code == "no_paired_link"' >/dev/null ||
    fail "no no_paired_link before pairing"

  pair_link "$assistant" "$key" >/dev/null
  send "$assistant" "one" >/dev/null
  send "$assistant" "two" >/dev/null
  [[ "$(unread "$key")" -eq 2 && "$(unread "$key")" -eq 2 ]] || fail "al status changed the unread count"
  [[ "$(link_status)" == "online" ]] && fail "al status made the Link online"
  start_wait "$key" "$work/status.out"
  eventually '[[ "$(wc -l <"$work/status.out")" -eq 2 ]]' 15 || fail "al wait did not print both messages"
  eventually '[[ "$(unread "$key")" -eq 0 ]]' 15 || fail "messages were not acknowledged"
  [[ "$(link_status)" == "online" ]] || fail "al status took the Link offline"
  send "$assistant" "three" >/dev/null
  eventually '[[ "$(wc -l <"$work/status.out")" -eq 3 ]]' 15 || fail "al wait stopped delivering after al status"
  [[ "$(texts "$work/status.out")" == "one,two,three" ]] || fail "wrong lines: $(texts "$work/status.out")"
  stop_wait "$waiter"
}

sql() { psql "${DATABASE_URL/ecto:/postgres:}" -Atc "$1"; }

# How many rows of the account ($1), and its users, the database still holds.
rows() {
  sql "select (select count(*) from assistants where account_id = '$1')
    + (select count(*) from assistant_links where account_id = '$1')
    + (select count(*) from assistant_events where account_id = '$1')
    + (select count(*) from text_messages where account_id = '$1')
    + (select count(*) from devices where account_id = '$1')
    + (select count(*) from memberships where account_id = '$1')
    + (select count(*) from accounts where id = '$1')
    + (select count(*) from users where id in (select user_id from memberships where account_id = '$1'))"
}

purge_with_no_grace_period() {
  (
    cd "$components/backend"
    env -u PHX_SERVER mix run -e '
      Application.put_env(:assistant_link, AssistantLink.Accounts, deletion_grace_period: 0)
      AssistantLink.Accounts.purge_deleted_accounts()'
  )
}

test_account_deletion() {
  step "5.5 a deleted account is unreachable at once, and gone after the purge"
  new_account
  local deleted_credential="$credential" deleted_account="$account_id"
  local assistant key unpaired unused_code code=0
  assistant="$(new_assistant)"
  key="$work/deleted.key"
  pair_link "$assistant" "$key"
  send "$assistant" "Hi" >/dev/null
  unpaired="$(api POST "/assistants/$assistant/links" | jq -r .link.id)"
  unused_code="$(api POST "/links/$unpaired/pairing_code" | jq -r .code)"
  start_wait "$key" "$work/deleted.out"
  eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online"

  new_account
  local other_account="$account_id"
  new_assistant >/dev/null
  credential="$deleted_credential"
  api DELETE /account

  eventually '! kill -0 "$waiter" 2>/dev/null' 15 || fail "al wait kept running after the account was deleted"
  wait "$waiter" || code=$?
  [[ "$code" -eq 4 ]] || fail "al wait exited $code after the account was deleted"
  code=0
  "$al" status --key-file "$key" >"$work/deleted.json" || code=$?
  [[ "$code" -eq 4 && "$(jq -r .check "$work/deleted.json")" == "rejected" ]] || fail "al status: $(cat "$work/deleted.json")"
  code=0
  "$al" send --key-file "$key" "Hi" >/dev/null || code=$?
  [[ "$code" -eq 4 ]] || fail "al send exited $code"
  code=0
  "$al" pair "$unused_code" --key-file "$work/deleted-again.key" >/dev/null || code=$?
  [[ "$code" -eq 4 ]] || fail "al pair with an unused code exited $code"
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$service/api/v1/assistants" -H "authorization: Bearer $credential")" == 401 ]] ||
    fail "the app credential still works"
  [[ "$(rows "$deleted_account")" -gt 0 ]] || fail "the data was deleted at once"

  purge_with_no_grace_period >"$work/purge.log" 2>&1 || { cat "$work/purge.log" >&2; fail "purge failed"; }
  [[ "$(rows "$deleted_account")" -eq 0 ]] || fail "rows are left after the purge"
  [[ "$(rows "$other_account")" -gt 0 ]] || fail "the purge deleted another account"
}
