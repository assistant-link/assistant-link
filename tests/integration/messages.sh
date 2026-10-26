# Text messages between the app and `al`. Sourced by smoke.sh once the backend is up; uses its helpers (api, step,
# fail, eventually, link_status, $al, $work). Every test creates its own account.
# A name ($2, or $1 for the other helpers) stands for the files $work/<name>.key and $work/<name>.out.

new_account() {
  credential=""
  account="$(api POST /accounts)"
  credential="$(jq -r .credential <<<"$account")"
  account_id="$(jq -r .account_id <<<"$account")"
}

new_assistant() {
  api POST /assistants '{"name": "Test", "avatar": "avatar-1"}' | jq -r .assistant.id
}

# Creates a Link on the Assistant ($1) and pairs it as $2. Its id is in $link_id.
pair_link() {
  local code
  link_id="$(api POST "/assistants/$1/links" | jq -r .link.id)"
  code="$(api POST "/links/$link_id/pairing_code" | jq -r .code)"
  "$al" pair "$code" --key-file "$work/$2.key" >/dev/null
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

# Starts `al wait` for $1; its pid is in $waiter.
start_wait() {
  AL_LINK_KEY="$(<"$work/$1.key")" "$al" wait >"$work/$1.out" &
  waiter=$!
}

stop_wait() {
  kill -INT "$1"
  wait "$1" || fail "al wait exited $? on SIGINT"
}

# Runs a command; its exit code is in $code and its output in $work/exits.out.
exits() {
  code=0
  "$@" >"$work/exits.out" || code=$?
}

texts() { jq -r .text_message.text "$work/$1.out" | paste -sd, -; }
delivery_status() { api GET "/assistants/$1/events" | jq -r --arg id "$2" '.events[] | select(.id == $id) | .delivery_status'; }
unread() { AL_LINK_KEY="$(<"$work/$1.key")" "$al" status | jq -r .unread_count; }
long_text() { head -c "$1" /dev/zero | tr '\0' x; }

test_delivery() {
  step "5.1 a message from the app reaches al wait and is delivered"
  new_account
  local assistant event
  assistant="$(new_assistant)"
  pair_link "$assistant" delivery
  start_wait delivery
  eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online"
  event="$(send "$assistant" "Hi")"
  eventually '[[ -s "$work/delivery.out" ]]' 15 || fail "al wait printed nothing"
  jq -e --arg id "$event" '.id == $id and .type == "text_message" and .deleted == false and .text_message == {text: "Hi"}' \
    "$work/delivery.out" >/dev/null || fail "unexpected line: $(<"$work/delivery.out")"
  eventually '[[ "$(delivery_status "$assistant" "$event")" == "delivered" ]]' 15 || fail "message was not delivered"
  stop_wait "$waiter"
}

test_catch_up() {
  step "5.2 messages sent before al wait arrive in order, once"
  new_account
  local assistant
  assistant="$(new_assistant)"
  pair_link "$assistant" catch-up
  send "$assistant" "one" >/dev/null
  send "$assistant" "two" >/dev/null
  start_wait catch-up
  eventually '[[ "$(texts catch-up)" == "one,two" ]]' 15 || fail "al wait printed: $(texts catch-up)"
  eventually '[[ "$(unread catch-up)" -eq 0 ]]' 15 || fail "messages were not acknowledged"
  stop_wait "$waiter"

  cp "$work/catch-up.key" "$work/restart.key"
  start_wait restart
  send "$assistant" "three" >/dev/null
  eventually '[[ "$(texts restart)" == "three" ]]' 15 || fail "after a restart al wait printed: $(texts restart)"
  stop_wait "$waiter"
}

test_two_links() {
  step "5.3 every Link gets every message; a later Link nothing older"
  new_account
  local assistant first second third
  assistant="$(new_assistant)"
  pair_link "$assistant" first
  pair_link "$assistant" second
  send "$assistant" "one" >/dev/null
  start_wait first
  first=$waiter
  start_wait second
  second=$waiter
  eventually '[[ "$(texts first)" == "one" && "$(texts second)" == "one" ]]' 15 || fail "a Link did not get the first message"

  pair_link "$assistant" third
  start_wait third
  third=$waiter
  send "$assistant" "two" >/dev/null
  eventually '[[ "$(texts first)" == "one,two" && "$(texts second)" == "one,two" && "$(texts third)" == "two" ]]' 15 ||
    fail "the Links got $(texts first) and $(texts second), the later one $(texts third)"
  stop_wait "$first"
  stop_wait "$second"
  stop_wait "$third"
}

test_unread_stdout() {
  step "5.4 a message nobody reads from stdout stays unacknowledged"
  new_account
  local assistant last reader
  assistant="$(new_assistant)"
  pair_link "$assistant" unread
  mkfifo "$work/unread.out"
  sleep 600 <"$work/unread.out" &
  reader=$!
  start_wait unread
  eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online"
  for _ in $(seq 40); do last="$(send "$assistant" "$(long_text 4000)")"; done
  sleep 3
  [[ "$(link_status)" == "online" ]] || fail "Link went offline while the write was pending"
  [[ "$(unread unread)" -gt 0 ]] || fail "every message was acknowledged"
  [[ "$(delivery_status "$assistant" "$last")" == "sent" ]] || fail "the last message was delivered"

  kill "$reader"
  exits wait "$waiter"; [[ $code -eq 1 ]] || fail "al wait did not exit 1 after stdout closed"
  eventually '[[ "$(link_status)" == "offline" ]]' 15 || fail "Link did not go offline"
  [[ "$(unread unread)" -gt 0 ]] || fail "the pending message was acknowledged"
}

test_send() {
  step "5.4 al send reaches the app"
  new_account
  local assistant id
  assistant="$(new_assistant)"
  pair_link "$assistant" send
  id="$(AL_LINK_KEY="$(<"$work/send.key")" "$al" send "Your reminder is set." | jq -r .message_id)"
  api GET "/assistants/$assistant/events" |
    jq -e --arg id "$id" '.events[] | select(.id == $id and .sender == "assistant" and .text_message.text == "Your reminder is set.")' \
      >/dev/null || fail "the app does not have the message"
  [[ "$(link_status)" == "offline" ]] || fail "al send changed the Link's presence"
  [[ "$(unread send)" -eq 0 ]] || fail "the Assistant's own message is deliverable"
  exits "$al" send --key-file "$work/send.key" "$(long_text 4001)"; [[ $code -eq 4 ]] || fail "al send of 4,001 characters did not exit 4"
}

test_status() {
  step "5.6 no_paired_link until pairing; al status disturbs nothing"
  new_account
  local assistant
  assistant="$(new_assistant)"
  link_id="$(api POST "/assistants/$assistant/links" | jq -r .link.id)"
  curl -sS -X POST "$service/api/v1/assistants/$assistant/messages" -H "authorization: Bearer $credential" \
    -H 'content-type: application/json' -d "{\"text\": \"Hi\", \"idempotency_key\": \"$(uuid7)\"}" |
    jq -e '.error.code == "no_paired_link"' >/dev/null || fail "no no_paired_link before pairing"

  pair_link "$assistant" status
  send "$assistant" "one" >/dev/null
  send "$assistant" "two" >/dev/null
  [[ "$(unread status)" -eq 2 && "$(unread status)" -eq 2 ]] || fail "al status changed the unread count"
  [[ "$(link_status)" == "online" ]] && fail "al status made the Link online"
  start_wait status
  eventually '[[ "$(texts status)" == "one,two" ]]' 15 || fail "al wait printed: $(texts status)"
  eventually '[[ "$(unread status)" -eq 0 && "$(link_status)" == "online" ]]' 15 || fail "not acknowledged, or not online"
  send "$assistant" "three" >/dev/null
  eventually '[[ "$(texts status)" == "one,two,three" ]]' 15 || fail "al wait stopped delivering after al status"
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

test_account_deletion() {
  step "5.5 a deleted account is unreachable at once, and gone after the purge"
  new_account
  local other_account assistant unpaired unused_code deleted_account
  new_account
  other_account=$account_id
  new_account
  deleted_account=$account_id
  assistant="$(new_assistant)"
  pair_link "$assistant" deleted
  send "$assistant" "Hi" >/dev/null
  unpaired="$(api POST "/assistants/$assistant/links" | jq -r .link.id)"
  unused_code="$(api POST "/links/$unpaired/pairing_code" | jq -r .code)"
  start_wait deleted
  eventually '[[ "$(link_status)" == "online" ]]' 15 || fail "Link did not go online"

  api DELETE /account

  exits wait "$waiter"; [[ $code -eq 4 ]] || fail "al wait did not exit 4 after the account was deleted"
  exits "$al" status --key-file "$work/deleted.key"
  [[ $code -eq 4 && "$(jq -r .check "$work/exits.out")" == "rejected" ]] || fail "al status: $code $(<"$work/exits.out")"
  exits "$al" send --key-file "$work/deleted.key" "Hi"; [[ $code -eq 4 ]] || fail "al send was not rejected"
  exits "$al" pair "$unused_code" --key-file "$work/again.key"; [[ $code -eq 4 ]] || fail "al pair was not rejected"
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$service/api/v1/assistants" -H "authorization: Bearer $credential")" == 401 ]] ||
    fail "the app credential still works"
  [[ "$(rows "$deleted_account")" -gt 0 ]] || fail "the data was deleted at once"

  # PHX_SERVER would make `mix run` start a second server on the same port.
  (
    cd "$components/backend"
    env -u PHX_SERVER mix run -e '
      Application.put_env(:assistant_link, AssistantLink.Accounts, deletion_grace_period: 0)
      AssistantLink.Accounts.purge_deleted_accounts()'
  ) >"$work/purge.log" 2>&1 || fail "purge failed: $(tail -n 5 "$work/purge.log")"
  [[ "$(rows "$deleted_account")" -eq 0 ]] || fail "rows are left after the purge"
  [[ "$(rows "$other_account")" -gt 0 ]] || fail "the purge deleted another account"
}
