# Design

## Context

The Assistant Link service, `al`, and the app can connect an agent to an Assistant and show whether it is online. See `proposal.md` for the slice and `specs/` for the required behavior. Today:

- The app derives "Assistant Link created" events from the Assistants list; the service stores no Timeline. An event's time comes from its Link's UUIDv7 id.
- The agent connection (`/alp/v1/connect`) is a JSON-RPC 2.0 WebSocket. Each connection is one process that tracks itself in `Phoenix.Presence`. The service sends only notifications, and `al wait` answers any request with `-32601`.
- The app's live connection (`/api/v1/connect`) is a JSON-RPC 2.0 WebSocket that forwards `link.status` notifications for the account.

Three principles shape the choices: use established protocols, keep the agent side free of state (`al` keeps nothing on the host), and build the delivery path once so later event types reuse it.

## Decisions

### The delivery retention, and the Timeline
The service stores every message the user sends and keeps it available for delivery to Assistant Links for **the delivery retention: 7 days** after it was sent. It is a single service setting with that default; tests set it to seconds. Every other mention of "7 days" in these artifacts means this value.

The Timeline (the app's conversation history) is separate: it keeps messages until the account is deleted, so "history survives relaunch" stays true and nothing needs deleting. The retention only bounds what an Assistant Link can still receive and catch up on, and when an undelivered message turns to "Not Delivered". It is enforced by a query on the message's time, not by deleting rows.

*Alternative:* expire the Timeline after 7 days too. Simpler storage story, but the conversation would silently shrink (open question 1).

### Events and the per-Link stream
An **event** is what the service delivers to an Assistant Link: `{"id", "type", …fields}`. Only `id` and `type` are required on every event; the other fields are defined per type. This slice has one type, `message`, with fields `text` and `sent_at`: the user's text messages. Its `id` is the message id (UUIDv7); delivery order is the message's `seq` (see "The cursor").

Events are stored, covered by the cursor, and caught up after a reconnect, within the retention. Later types (calls, audio, requests) add `type` values and reuse the same delivery, cursor, and `al wait` line format.

### Delivery to the agent: a JSON-RPC request, `event.deliver`
The service delivers an event with a request on an open agent connection whose params are the event, exactly the line `al wait` prints:

```json
{"jsonrpc": "2.0", "id": "0199…", "method": "event.deliver",
 "params": {"id": "0199…", "type": "message", "text": "Hi", "sent_at": "2026-10-21T09:30:00.123Z"}}
```

The agent's response is the acknowledgement: `{"jsonrpc": "2.0", "id": "0199…", "result": {}}`. `result` is an object so later revisions can add fields. An error response, no response within 30 seconds (the *attempt timeout*), or a connection that closes first means the attempt failed and the event is not acknowledged. The request `id` is the event's `id`, so a response that arrives late for the event currently in flight is still accepted as its acknowledgement and cancels the retry; a response for any other id is ignored.

An agent that predates this slice answers `-32601` (the existing forward-compatibility rule), so the event stays unacknowledged instead of silently vanishing. This is also why delivery is a request and not a notification: a notification could never tell "taken" apart from "lost".

*Alternative:* a `message.deliver` request specific to messages. Rejected: every new event type would need its own method, ack rules, and cursor.

### The cursor: one per Assistant Link, owned by the service
The service tracks, for each Assistant Link, the `seq` of the last event the Link acknowledged (`assistant_links.delivered_through`, a bigint). `seq` is a per-Assistant sequence assigned to each user message in the transaction that stores it (see "Message storage"), so it follows commit order, which a UUIDv7 does not. The agent keeps no state and passes no position; this matches `al` keeping nothing on the host.

- **One unacknowledged event per Link at a time, in `seq` order.** The service sends the next event only after the previous one was acknowledged, so a single cursor is exact: everything up to it was taken, nothing after it was.
- **Acknowledgement advances the cursor.** The response to `event.deliver` sets the Link's cursor to that event's `seq` and, for a message, marks it delivered (below).
- **A lost acknowledgement means redelivery.** If the response never arrives (connection dropped, error, or the attempt timeout), the cursor stays and the same event is sent again, with the same `id`. Delivery is at least once; readers dedupe by `id`.
- **Catch-up is the same mechanism.** After `connection.ready` the service sends the first event after the cursor that is within the retention, then the next after each acknowledgement, until none is left. Events older than the retention are skipped. New events are sent the same way once their transaction commits. `al` has nothing extra to implement.
- **A new Link starts at its pairing time.** In the pairing transaction the cursor is set to the Assistant's current `last_message_seq`, so the Link receives messages sent after it, not the older history.
- **Several connections of one Link share its cursor.** The newest open connection receives the event. If it answers with an error, closes, or times out, the service tries the next-newest one that has not failed this round; after every open connection failed a round, it waits 30 seconds, doubling after each failed round up to 5 minutes, and starts over. A new connection resets the wait and starts a round at once. An event is never sent to two connections at once, but a connection may have written the line before it failed, so the next one can write it again (at least once).
- **Links are independent.** Each Link of the Assistant has its own cursor and its own pace: a slow or broken Link never holds back another.

A **delivery process** per online Link does this. It starts when the Link's first agent connection opens and stops when its last closes (a `DynamicSupervisor`, registered under a `:global` name keyed by `link_id`, so there is one per Link across nodes). It holds the one event in flight, the connections already tried, and a timer. It runs when a connection opens, when a "message stored" notice for the Link's Assistant arrives, on each acknowledgement, and when the timer fires. The notice is broadcast on PubSub after the storing transaction commits, so it reaches the owning node, and a message stored while the process is starting is found by its first query. The query is `seq > delivered_through`, sender `user`, sent within the retention, oldest first, limit 1, so a restart loses nothing: the cursor is in the database. The cursor update is monotonic (`WHERE delivered_through < $seq`), so a late or duplicate acknowledgement never moves it back. The service runs on one node today; this does not block more.

Each agent connection process already tracks itself in Presence under its `link_id`; it adds its pid and the time it opened to the Presence metadata. The delivery process sends `{:deliver, request}` to a connection process, which writes the frame and tells the delivery process when the response arrives. The connection process is the only writer to its socket, so ordering and liveness behave as today. A response whose `id` is not the event in flight is ignored.

*Alternative:* the agent passes a position when it connects (`al wait --since <id>`). Needs agent state and says nothing the service does not already know.

*Alternative:* several events in flight with an acknowledged range. A lost ack in the middle needs a per-event state; one at a time is exact and fast enough for text.

### Message states
A message of the user has one stored state, `status`:

| `status`    | Meaning                                                                 | Caption in the app |
| ----------- | ----------------------------------------------------------------------- | ------------------ |
| `sent`      | Stored by the service.                                                  | "Sent"             |
| `delivered` | At least one Assistant Link acknowledged it.                            | "Delivered"        |
| `expired`   | No Assistant Link acknowledged it within the delivery retention.        | "Not Delivered"    |

The app adds two states of its own that are never stored: "Sending…" (the request to the service is in flight) and "Not Delivered" when the service rejected the message or could not be reached.

- **`sent` or `expired` becomes `delivered`** on the first acknowledgement by any Link, with a conditional update (`WHERE status IN ('sent', 'expired')`), so it happens once. An acknowledgement that races the expiry job wins: a Link did take the message. The service then sends the app `message.updated`. Acknowledgements by other Links change nothing visible.
- **`sent` becomes `expired`** when the message is older than the retention and still undelivered. A periodic job (each minute, on one node only, under a Postgres advisory lock) makes this update and sends `message.updated`; delivery itself needs no job, because the query above already excludes messages older than the retention. If the job lags, the message is merely labelled late.
- Only the latest of the user's messages shows "Sent" or "Delivered", as Apple Messages does. "Sending…" and "Not Delivered" show on every message they apply to, because they need attention.
- An expired message is final: no "Try Again" (open question 3). A message the app could not send (rejected or unreachable) is retried by posting it again with the same `client_id`; that is idempotent (below), and the message is stored at that time, so it moves to the bottom of the Timeline.

### The agent sends over HTTP: `POST /alp/v1/messages`
```
POST /alp/v1/messages          Authorization: Bearer <Link token>
{"text": "Your reminder is set."}
→ 201 {"message_id": "0199…", "sent_at": "2026-10-21T09:31:00.456Z"}
```

An optional `client_id` (string, unique per Assistant Link) makes the request idempotent: a repeat returns `200` with the stored message and stores nothing. A repeated `client_id` with a different text is rejected with `409 client_id_conflict`. It is additive within v1.

Errors use the HTTP error format: `422 invalid_params` (missing or not a string), `422 text_empty` (empty or only Unicode White_Space characters), `422 text_too_long` (more than 4,000 Unicode code points), and `401 unauthorized`, and `409 client_id_conflict`. The app, `al`, and the service count and test text the same way (shared test vectors).

Why HTTP and not a JSON-RPC method on the agent connection? `al send` is a short-lived process. If it opened its own agent connection it would flip the Link's presence to online for a moment (the app shows it live within 2 seconds), and, as the newest connection, it could be chosen to receive the user's messages and exit before reading them. An HTTP request touches neither. It also lets an agent send without holding a WebSocket at all, which is the common case for a script. The service accepts it from any valid Link token, whether or not the Link is online, and it does not change presence or last active time.

A message an agent sends is stored and shown in the Timeline. It is **not** delivered to the Assistant's other Links in this slice (open question 4): they are separate agent installations and the sending agent knows what it said. It would be a new event `type` later.

### Message storage
`messages(id, account_id, assistant_id, seq null, sender, text, status null, client_id null, link_id null, inserted_at)`:

- `id`: UUIDv7, the API identifier and the paging key of the Timeline. `sent_at` in the API is `inserted_at`.
- `seq`: for the user's messages, a per-Assistant bigint assigned in the insert transaction with `UPDATE assistants SET last_message_seq = last_message_seq + 1 … RETURNING`, which holds a row lock on the Assistant until commit. Sequences therefore follow commit order, and delivery order is `seq`. Null for the Assistant's messages.
- `sender`: `user` or `assistant`. `status` is `sent`, `delivered`, or `expired` for the user's messages and null for the Assistant's.
- `(account_id, assistant_id)` references `assistants` with `ON DELETE CASCADE`, like every tenant-owned table, so deleting the account deletes its messages. Indexes on `(assistant_id, id)` for paging and `(assistant_id, seq)` for the delivery query. `client_id` is unique per account for the user's messages and unique per `link_id` for the Assistant's (`link_id` is null for the user's).
- `text` is stored as given (not trimmed, line breaks kept), 1–4,000 Unicode code points (scalar values), not only Unicode White_Space characters.

The cursor is one new nullable column on `assistant_links`: `delivered_through` (bigint, a message `seq`), set at pairing and deleted with the Link. It needs no table of its own: a Link has exactly one. `assistants` gains `last_message_seq` (bigint, default 0). Retention is enforced by the time condition in the query and by the `expired` update; no rows are deleted.

*Why store messages in the service?* The Timeline is the per-Assistant history, and the app is a client of it; there is no local database in the app. Storing them durably also lets an offline Link catch up.

### Client API
All under `/api/v1`, with the account credential:

- `POST /assistants/:id/messages` with `{"client_id": "<uuid>", "text"}` → `201 {"message": message}` as soon as the message is stored, with status `sent`. Delivery happens afterwards. `client_id` makes it idempotent: repeating a request with a `client_id` already used returns `200` with the stored message in its current state and stores nothing. This is "Try Again": there is no separate retry endpoint. A repeated `client_id` with a different text or Assistant is `409 client_id_conflict`. Same errors as above for the text (`422`); an unknown Assistant is `404`.
- `GET /assistants/:id/messages?limit=50&before=<message id>` → `{"messages": [message], "has_more": bool}`, the newest `limit` messages older than `before` (or the newest of all), returned oldest first. `limit` defaults to 50 and is at most 100.
- The Assistants list adds `"latest_message": message | null` to each Assistant, so the home screen needs no history.

A message is `{"id", "assistant_id", "sender", "text", "sent_at", "status", "client_id"}`; `status` and `client_id` are `null` for the Assistant's messages in the API. The app matches its local "Sending…" or "Not Delivered" bubble to the stored message by `client_id`.

The app's live connection sends, to every app connection of the account:

- `message.created` with `{"message": message}` for each message from the Assistant.
- `message.updated` with `{"message": message}` when a message of the user becomes `delivered` or `expired`. The app ignores one for a message it has not loaded.

The user's own new messages need no notification: the app that sends one gets it in the response.

### App: Timeline
The conversation screen merges two lists by time: the loaded messages and the derived "Assistant Link created" events. Both are oldest first; the newest is at the bottom, where the screen scrolls on open and on every new message, as it does today.

- History: the app asks for the latest 50 messages. When `has_more` is true, a "Load Earlier Messages" button heads the Timeline and loads the 50 before the oldest one, keeping the scroll position. *Alternative:* load everything. Simplest, but unbounded.
- The "Assistant Link created" events are shown only when they are newer than the oldest loaded message, or when `has_more` is false. This keeps an event from appearing above messages that are not loaded yet.
- While open, `message.created` for this Assistant appends a message and `message.updated` replaces the message with the same id. For another Assistant they update that row's latest-message preview only. Returning to the foreground refetches the latest 50 and merges by id, the stored message winning, so a state change missed while the app was away appears.
- A message sent by the user is added immediately as "Sending…" with its `client_id`, and replaced by the service's message when the response arrives. If the service rejects it, cannot be reached, or gives no response after 15 seconds, the app marks the message "Not Delivered" locally; "Try Again" posts again with the same `client_id` (the service answers with the stored message if the first request did arrive). A message that was not stored before is stored now, so it moves to the bottom of the Timeline.
- Only the latest of the user's messages shows "Sent" or "Delivered"; an `expired` message shows "Not Delivered" but offers no "Try Again".
- The offline notice follows the live status; the composer stays enabled.

### Assistant list preview
`latest_message` and the latest Link event compete by time. The row shows the message text on one line with "You: " in front for the user's messages, or "Assistant Link created" when that event is newer, and keeps the time on the right. A latest message that is Not Delivered (expired, or failed in the app) shows a small red exclamation mark before the text.

### `al send`
```
al send "Your reminder is set."      text as an argument
echo "multi line…" | al send -        text from standard input
```

- Text is one argument, or `-` to read standard input until end of file as UTF-8 (a single trailing newline is dropped, the Unix habit for `echo`). With no argument it is a usage error. Stdin avoids shell quoting problems and argument-length limits, and keeps the text out of `ps`.
- It reads the Link key like `al status` and calls `POST /alp/v1/messages`. It never opens the agent connection (see above).
- On success it prints `{"message_id", "sent_at"}` and exits 0; on failure `{"error": {"code", "message"}}`. `al` does not check the length itself: the service's limit can change. A rejected text (`text_empty`, `text_too_long`, `invalid_params`) exits with the "rejected" exit code (4); `unauthorized` is also 4; an unreachable service is 5; a missing key is 3. `al send` makes one attempt, sends no `client_id`, and does not retry: an agent that retries after exit 5 may send the message twice, unless it calls the API directly with a `client_id`. Existing exit codes keep their meaning: 4 is now "rejected by the service" in general (code, key, or message).

### `al wait` event format
Standard output of `al wait` carries incoming events, one JSON object per line (JSON Lines), always compact on one line, in both JSON and `--human` modes: it is a data stream, and `--human` changes only the status messages on standard error. Every event has a `type`, and the line is the `params` of `event.deliver`:

```json
{"type": "message", "id": "0199…", "text": "Hi", "sent_at": "2026-10-21T09:30:00.123Z"}
```

- `type` is the discriminator. Later event types (calls, audio, requests) add new `type` values and their own fields; existing types only gain optional fields. A reader MUST ignore unknown fields and SHOULD skip lines whose `type` it does not know.
- `id` is the service's event id, so a reader can drop duplicates. After a reconnect, or after a lost acknowledgement, the same line can appear again.
- Lines arrive in order, and missed events come first: after a reconnect `al wait` prints what the Link missed within the retention before anything newer.
- `al wait` answers `event.deliver` with the acknowledgement only after the line has been written and flushed to standard output: write, flush, then acknowledge. The write must not block the connection (the Link would go offline and stop answering): it runs off the connection loop with a 5 second timeout. If it fails or times out (for example the reader closed the pipe or stopped reading), `al wait` answers with error `-32001`, reason `not_received`, reports it on standard error, and keeps running; the Assistant Link stays online. The Link's cursor did not move, so the service sends the event again later. Agents must read `al wait`'s standard output, and `install.md` says so.
- Every other notification and request is handled as today (unknown notifications ignored, unknown requests answered `-32601`).

### Security implications
- The text is end-user content that usually reaches a model. The service passes it through unchanged and never executes it; the agent owns that trust boundary.
- The service now keeps the user's text readable for longer: in the database until the account is deleted (the Timeline), and available for delivery for 7 days. It is stored in the clear like the rest of the Assistant's data; end-to-end encryption is out of scope. It is deleted with the account, together with every cursor. Message text is not logged.
- Every Assistant Link of an Assistant receives the user's messages, not one. A Link is a separate agent installation, possibly on another host, so the user should create a Link only for an agent they trust with that Assistant's conversation. A Link receives only messages sent after it was paired.
- A leaked Link token also allows spoofed messages from that Link's Assistant (the same trust it already carries for presence), and reading the user's messages from the last 7 days from the Link's cursor onward. A Link can acknowledge only for itself: it cannot move another Link's cursor, but it can make a message show "Delivered" without any model reading it. "Delivered" means an agent process took it, nothing more.
- Account scoping holds: client endpoints only see the account's Assistants and messages (`404` otherwise), and a message goes only to Links of its own Assistant.
- Rate limiting and request size limits, beyond the 4,000 character limit, are left for security hardening (non-goal).

### UI designs
Design source and PNG exports live in this change's `designs/` folder. The `.fig` file opens in OpenPencil (openpencil.dev). The PNGs are the reviewable artifact; if they disagree with the specs, the specs win. The screens are redrawn from the descriptions below whenever those change.

All screens use the app's existing style (system fonts, the navigation-bar bubble with the Assistant's avatar, name, and status; centered grey captions for system events) and the Assistant "Hermes".

![Overview: all screens side by side](designs/overview.png)

![Conversation: messages from both sides mixed with system events](designs/01-conversation.png)

![Composer with text typed](designs/02-composer-typing.png)

![A message sending, then sent and delivered](designs/03-sending-sent.png)

![A message that could not be sent, with the retry affordance](designs/04-failed.png)

![Conversation while the Assistant is offline](designs/05-assistant-offline.png)

![Assistant list with latest message previews](designs/06-assistant-list.png)

![Conversation in dark mode](designs/07-conversation-dark.png)

The expired "Not Delivered" variant (red caption, no "Try Again") is specified in the messages spec but not drawn. The "Load Earlier Messages" state is specified in the messages spec but not drawn: the drawn conversations are short, so `has_more` is false and the "Assistant Link created" event is shown. Time captions use the form "Oct 20, 9:12 AM", or "Today 9:30 AM" for today.

What each screen must show:

- **01-conversation** (light, Assistant online). Navigation bar as today. Timeline, oldest first, newest at the bottom: the centered caption "Oct 20, 9:12 AM" over "Assistant Link created" with the link icon and "Link 1"; the user's message, right-aligned in an accent-colored bubble with white text ("Can you remind me to call David tomorrow at 10?"); the Assistant's reply, left-aligned in a grey bubble ("Done. I set a reminder for tomorrow at 10:00."); a further user message; the latest user message has the caption "Delivered" in small grey text under its bubble, right-aligned. Earlier user messages have no caption. Time captions separate messages more than an hour apart. Below the Timeline the composer: a rounded text field with the placeholder "Message", empty, and a send button to its right in the disabled (grey) state.
- **02-composer-typing**. Same screen with the keyboard up and the text "Also add it to my calendar" in the field; the send button is an accent-colored circle with an up-arrow, enabled. The Timeline above scrolls so the last message stays visible.
- **03-sending-sent**. The states of the latest user message, shown for one message: the screen draws the moment it is sending. Two user bubbles at the bottom, no Assistant message between them; the older one has no caption. The newer one is still sending: its bubble is slightly dimmed (reduced opacity) and its caption is "Sending…" in grey. A note beside the screen (not part of the app) says that when the service stores it the caption becomes "Sent", and when an Assistant Link acknowledges it, "Delivered", with the bubble at full opacity. Composer empty.
- **04-failed**. A message the app could not send, with the Assistant online and no offline notice; the navigation-bar bubble shows "Online" with the green dot. The user's latest message with a red exclamation-mark circle to the right of its bubble and the red caption "Not Delivered" under it. A confirmation dialog (iOS action sheet from the bottom) opened by tapping the message: buttons "Try Again" and "Cancel". The sheet covers the composer.
- **05-assistant-offline**. The navigation-bar bubble shows "Offline" with no green dot. The user's latest message has the caption "Sent" (stored, waiting for an Assistant Link). Above the composer, a single-line notice on a tinted strip: "Hermes is offline. Messages will be delivered when it connects." The composer is enabled with the placeholder "Message".
- **06-assistant-list**. Title "Assistants". Rows of avatar (green dot while online), name, time at the right, and a one-line preview: "Hermes" (online) with the user's latest message "You: Thanks! Please also move my 2 pm meeting to 3." and "9:30 AM" (consistent with 01); "Grok Bot" (offline) with "You: Summarize today's news" and "Yesterday"; "Muse" (offline) with a red exclamation mark followed by "You: Are you there?" and "Oct 12" (a message older than 7 days that no Assistant Link took, so Not Delivered); and "Atlas" (purple avatar, a Link not yet connected) with "Assistant Link created" and "Oct 8". Previews are one line, truncated with an ellipsis.
- **07-conversation-dark**. Screen 01 in dark mode: dark background, the Assistant's bubble in dark grey, the user's bubble in the accent color, captions in secondary grey.

## Risks / Trade-offs

- [A lost acknowledgement redelivers an event the agent already read] → Documented as at least once; the same `id` lets agents drop duplicates.
- [Head-of-line blocking: an agent that cannot take an event (for example an older `al`) holds back the later ones for that Link, retried with backoff from 30 seconds to 5 minutes] → Accepted: an agent that never acknowledges (for example an older `al`) holds that Link's stream until it upgrades or the messages expire after 7 days; other Links are unaffected. A newer `al` then catches up at once.
- [The Timeline keeps every message until account deletion, so `messages` grows without bound] → Indexes on `(assistant_id, seq)` and `(assistant_id, id)`; partitioning later if needed.
- [A message typed before an Assistant Link is paired is never delivered to it] → The cursor starts at pairing (open question 2). In practice the user pastes the pairing text first; the message shows "Sent" and finally "Not Delivered" if no other Link takes it.
- [A message needs the agent to run `al wait` (or an equivalent connection) at some point within 7 days] → By design. `install.md` already tells agents to keep `al wait` running; it also gains how to read events.

## Migration Plan

Additive. Deploy the service first: a migration adds the `messages` table and `assistant_links.delivered_through` (existing Assistants start at `last_message_seq` 0 and existing Links at cursor 0, so they receive messages sent after the migration). ALP and the client API only gain endpoints and a method. Agents that do not implement `event.deliver` answer `-32601`: their Link's messages stay "Sent" until a newer `al` connects, and then catch up, if within 7 days. Then release `al` (so `al wait` can receive and `al send` can reply) and the app. Rolling back the service leaves the extra column and table unused.

## Open Questions

See `proposal.md`. Beyond those, left for later: an agent-chosen start position (`al wait --since <id>`), an agent-side `message.send` JSON-RPC method, live-only event types, and a failure reason in the message.
