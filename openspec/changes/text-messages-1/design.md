# Design

## Context

The Assistant Link service, `al`, and the app can connect an agent to an Assistant and show whether it is online. See `proposal.md` for the slice and `specs/` for the required behavior. Today:

- The app derives "Assistant Link created" events from the Assistants list; the service stores no Timeline. An event's time comes from its Link's UUIDv7 id.
- The agent connection (`/alp/v1/connect`) is a JSON-RPC 2.0 WebSocket. Each connection is one process that tracks itself in `Phoenix.Presence`. The service sends only notifications, and `al wait` answers any request with `-32601`.
- The app's live connection (`/api/v1/connect`) is a JSON-RPC 2.0 WebSocket that forwards `link.status` notifications for the account.

Two principles shape the choices: use established protocols, and keep the server doing little per message.

## Decisions

### Delivery to the agent: a JSON-RPC request, `message.deliver`
The service delivers a user's message with a request on an open agent connection:

```json
{"jsonrpc": "2.0", "id": "d-1", "method": "message.deliver",
 "params": {"message_id": "0199…", "text": "Hi", "sent_at": "2026-10-21T09:30:00.123Z"}}
```

The agent's response is the receipt: `{"jsonrpc": "2.0", "id": "d-1", "result": {}}`. Only then is the message `sent`. `result` is an object so later revisions can add fields. An error response, no response within 10 seconds, or a connection that closes first means this attempt failed.

An agent that predates this slice answers `-32601` (the existing forward-compatibility rule), so the message fails instead of silently vanishing. This is also why delivery is a request and not a notification: a notification could never tell the user "Sent" apart from "lost".

`message_id` is stable: a retry sends the same id, so an agent can drop a duplicate. A receipt can be lost after the agent has the message (for example the connection drops right after `al wait` wrote the line), so delivery is at least once from the user's point of view: they may see "Not Delivered" for a message the agent did read.

*Alternative:* a `message.received` notification with no receipt. Rejected: the app could not show sent or failed.

### The agent sends over HTTP: `POST /alp/v1/messages`
```
POST /alp/v1/messages          Authorization: Bearer <Link token>
{"text": "Your reminder is set."}
→ 201 {"message_id": "0199…", "sent_at": "2026-10-21T09:31:00.456Z"}
```

The body may also carry an optional `client_id` (string, unique per Assistant Link). Repeating it returns `200` with the stored `{"message_id", "sent_at"}` and stores no duplicate, so an agent can retry a request that timed out. It is additive within v1; `al send` does not expose it in this slice.

Errors use the HTTP error format: `422 invalid_params` (missing or not a string), `422 text_empty` (empty or only Unicode White_Space characters), `422 text_too_long` (more than 4,000 Unicode code points), and `401 unauthorized`. The app, `al`, and the service count and test text the same way (shared test vectors).

Why HTTP and not a JSON-RPC method on the agent connection? `al send` is a short-lived process. If it opened its own agent connection it would flip the Link's presence to online for a moment (the app shows it live within 2 seconds), and, as the newest connection, it could be chosen to receive the user's messages and exit before reading them. An HTTP request touches neither. It also lets an agent send without holding a WebSocket at all, which is the common case for a script. The service accepts it from any valid Link token, whether or not the Link is online, and it does not change presence or last active time.

*Alternative:* a `message.send` request on the agent connection, which suits an agent that already holds one. Not needed yet; it can be added later within v1, and `al` would stay on HTTP.

### Which connection receives a user's message
- **Which Link:** the service picks the first *online* Link of the Assistant in creation order. If none is online, or the Assistant has none, the message is stored as `failed` at once without an attempt (the app shows the setup guide, not the composer, while the Assistant has no Links). It does not try other Links when the chosen one fails: one Link, one result, a simple rule to explain to the user. *Alternative:* most recently active Link, or try each online Link in turn. Both are better for users with several Links and are an additive change later (open question 1).
- **Which connection of that Link:** the newest open connection first. If it answers with an error or closes, the service tries the next-newest, and so on, all within the one 10 second deadline. The first receipt wins. A request is never sent to two connections at once, but the fallback is at-least-once too: a connection may have written the line before it closed or answered with an error, and then the next one writes it again. Agents dedupe by message id.

*Alternative:* send to every connection and take the first receipt. Cheaper to implement and fast, but two `al wait` processes would always both print the message.

Each agent connection process already tracks itself in Presence under its `link_id`. It adds its pid and the time it opened to the Presence metadata. The delivery task reads the Link's entries, sorts by that time, and sends `{:deliver, request}` to the connection process, which writes the frame and keeps `id → waiting task` until the response arrives. The connection process is the only writer to its socket, so ordering and liveness behave as today.

### The delivery attempt outlives the request
`POST /api/v1/assistants/:id/messages` inserts the message as `sending`, runs the attempt in a supervised `Task`, waits for it, and answers with the final message. The Task, not the HTTP request process, writes the final status, so an app that is closed or loses network mid-send still leaves `sent` or `failed` in the Timeline. The Task is in-process, so a restart can lose it: on service start (and periodically) the service marks `sending` messages older than the deadline as `failed`. If the message or the account is deleted mid-attempt, the Task just stops.

### Message storage
`messages(id, account_id, assistant_id, link_id null, sender, text, status null, client_id null, inserted_at)`:

- `id`: UUIDv7, so ordering by id is Timeline order. `sent_at` in the API is `inserted_at`.
- `sender`: `user` or `assistant`. `status` is `sending`, `sent`, or `failed` for the user's messages and null for the Assistant's. `link_id` is the Link that received or sent it, kept for later use and not shown.
- `(account_id, assistant_id)` references `assistants` with `ON DELETE CASCADE`, like every tenant-owned table, so deleting the account deletes its messages. Index on `(assistant_id, id)` for paging. `client_id` is unique per account for the user's messages and per `link_id` for the Assistant's (two partial unique indexes); the API shows it only on the user's messages.
- `text` is stored as given (not trimmed, line breaks kept), 1–4,000 Unicode code points (scalar values), not only Unicode White_Space characters.

*Why store messages in the service?* The Timeline is the per-Assistant history, and the app is a client of it; there is no local database in the app.

### Client API
All under `/api/v1`, with the account credential:

- `POST /assistants/:id/messages` with `{"client_id": "<uuid>", "text"}` → `201 {"message": message}` once the attempt finished. `client_id` makes it idempotent: repeating a request with a `client_id` already used returns `200` with the stored message. If that message is `failed`, the service first moves it back to `sending` with a compare-and-set update (so a double tap or two requests start only one attempt) and attempts again, with the same message id and Timeline place, and answers `200` with the final message; if it is `sending` or `sent`, it attempts nothing. This is "Try Again": there is no separate retry endpoint. Same errors as above for the text (`422`); an unknown Assistant is `404`.
- `GET /assistants/:id/messages?limit=50&before=<message id>` → `{"messages": [message], "has_more": bool}`, the newest `limit` messages older than `before` (or the newest of all), returned oldest first. `limit` defaults to 50 and is at most 100.
- The Assistants list adds `"latest_message": message | null` to each Assistant, so the home screen needs no history.

A message is `{"id", "assistant_id", "sender", "text", "sent_at", "status", "client_id"}`; `status` and `client_id` are `null` for the Assistant's messages. The app matches its local "Sending…"/"Not Delivered" bubble to the stored message by `client_id`. `failed` carries no reason in this slice.

The app's live connection sends the notification `message.created` with `{"message": message}` for each message from the Assistant, to every app connection of the account. The user's own messages need no notification: the app that sends one gets it in the response, and multi-device sync is a non-goal.

Nothing is queued: a failed message is delivered again only if the user taps "Try Again", which goes to whichever Link is then chosen.

### App: Timeline
The conversation screen merges two lists by time: the loaded messages and the derived "Assistant Link created" events. Both are oldest first; the newest is at the bottom, where the screen scrolls on open and on every new message, as it does today.

- History: the app asks for the latest 50 messages. When `has_more` is true, a "Load Earlier Messages" button heads the Timeline and loads the 50 before the oldest one, keeping the scroll position. *Alternative:* load everything. Simplest, but unbounded.
- The "Assistant Link created" events are shown only when they are newer than the oldest loaded message, or when `has_more` is false. This keeps an event from appearing above messages that are not loaded yet.
- While open, `message.created` for this Assistant appends a message. For another Assistant it updates that row's latest-message preview only. Returning to the foreground refetches the latest 50 and merges by id.
- A message sent by the user is added immediately as "Sending…" with its `client_id`, and replaced by the service's message when the response arrives. If the app cannot reach the service, or has no response after 15 seconds (the service answers within about 10), it marks the message "Not Delivered" locally; "Try Again" posts again with the same `client_id`.
- Only the user's most recent `sent` message shows "Sent", as iMessage does.
- The offline notice follows the live status; the composer stays enabled (open question 2).

### Assistant list preview
`latest_message` and the latest Link event compete by time. The row shows the message text on one line with "You: " in front for the user's messages, or "Assistant Link created" when that event is newer, and keeps the time on the right. A failed latest message shows a small red exclamation mark before the text.

### `al send`
```
al send "Your reminder is set."      text as an argument
echo "multi line…" | al send -        text from standard input
```

- Text is one argument, or `-` to read standard input until end of file as UTF-8 (a single trailing newline is dropped, the Unix habit for `echo`). With no argument it is a usage error. Stdin avoids shell quoting problems and argument-length limits, and keeps the text out of `ps`.
- It reads the Link key like `al status` and calls `POST /alp/v1/messages`. It never opens the agent connection (see above). It does not send a `client_id` in this slice.
- On success it prints `{"message_id", "sent_at"}` and exits 0; on failure `{"error": {"code", "message"}}`. `al` does not check the length itself: the service's limit can change. A rejected text (`text_empty`, `text_too_long`, `invalid_params`) exits with the "rejected" exit code (4); `unauthorized` is also 4; an unreachable service is 5; a missing key is 3. Existing exit codes keep their meaning: 4 is now "rejected by the service" in general (code, key, or message).

### `al wait` event format
Standard output of `al wait` carries incoming events, one JSON object per line (JSON Lines), always compact on one line, in both JSON and `--human` modes: it is a data stream, and `--human` changes only the status messages on standard error. Every event has a `type`:

```json
{"type": "message", "id": "0199…", "text": "Hi", "sent_at": "2026-10-21T09:30:00.123Z"}
```

- `type` is the discriminator. Later event types (calls, audio, requests) add new `type` values and their own fields; existing types only gain optional fields. A reader MUST ignore unknown fields and SHOULD skip lines whose `type` it does not know.
- `id` is the service's message id, so a reader can drop duplicates.
- `al wait` answers `message.deliver` with the receipt only after the line has been written and flushed to standard output. The write must not block the connection (the Link would go offline and stop answering): it runs off the connection loop with a 5 second timeout. If it fails or times out (for example the reader closed the pipe or stopped reading), `al wait` answers with error `-32001`, reason `not_received`, reports it on standard error, and keeps running; the Assistant Link stays online. Agents must read `al wait`'s standard output, and `install.md` says so.
- Every other notification and request is handled as today (unknown notifications ignored, unknown requests answered `-32601`).

### Security implications
- The text is end-user content that usually reaches a model. The service passes it through unchanged and never executes it; the agent owns that trust boundary.
- A leaked Link token also allows spoofed messages from that Link's Assistant, the same trust it already carries for presence.
- Account scoping holds: client endpoints only see the account's Assistants and messages (`404` otherwise), and a message goes only to Links of its own Assistant.
- Rate limiting and request size limits, beyond the 4,000 character limit, are left for security hardening (non-goal).
- Message text is not logged. It is stored in the clear like the rest of the Assistant's data; end-to-end encryption is out of scope.

### UI designs
Design source and PNG exports live in this change's `designs/` folder. The `.fig` file opens in OpenPencil (openpencil.dev). The PNGs are the reviewable artifact; if they disagree with the specs, the specs win.

All screens use the app's existing style (system fonts, the navigation-bar bubble with the Assistant's avatar, name, and status; centered grey captions for system events) and the Assistant "Hermes".

![Overview: all screens side by side](designs/overview.png)

![Conversation: messages from both sides mixed with system events](designs/01-conversation.png)

![Composer with text typed](designs/02-composer-typing.png)

![A message sending, the previous one sent](designs/03-sending-sent.png)

![A failed message with the retry affordance](designs/04-failed.png)

![Conversation while the Assistant is offline](designs/05-assistant-offline.png)

![Assistant list with latest message previews](designs/06-assistant-list.png)

![Conversation in dark mode](designs/07-conversation-dark.png)

The "Load Earlier Messages" state is specified in the messages spec but not drawn: the drawn conversations are short, so `has_more` is false and the "Assistant Link created" event is shown. Time captions use the form "Oct 20, 9:12 AM", or "Today 9:30 AM" for today.

What each screen must show:

- **01-conversation** (light, Assistant online). Navigation bar as today. Timeline, oldest first, newest at the bottom: the centered caption "Oct 20, 9:12 AM" over "Assistant Link created" with the link icon and "Link 1"; the user's message, right-aligned in an accent-colored bubble with white text ("Can you remind me to call David tomorrow at 10?"); the Assistant's reply, left-aligned in a grey bubble ("Done. I set a reminder for tomorrow at 10:00."); a further user message; the latest user message has the caption "Sent" in small grey text under its bubble, right-aligned. Time captions separate messages more than an hour apart. Below the Timeline the composer: a rounded text field with the placeholder "Message", empty, and a send button to its right in the disabled (grey) state.
- **02-composer-typing**. Same screen with the keyboard up and the text "Also add it to my calendar" in the field; the send button is an accent-colored circle with an up-arrow, enabled. The Timeline above scrolls so the last message stays visible.
- **03-sending-sent**. Two user bubbles at the bottom, no Assistant message between them. The older one is sent and carries the caption "Sent". The newer one is still sending: its bubble is slightly dimmed (reduced opacity) and its caption is "Sending…" in grey. When the newer one is sent, "Sent" moves to it. Composer empty.
- **04-failed**. The user's message with a red exclamation-mark circle to the right of its bubble and the red caption "Not Delivered" under it. A confirmation dialog (iOS action sheet from the bottom) opened by tapping the message: buttons "Try Again" and "Cancel". The sheet covers the composer, and the offline notice (see 05) sits directly above the sheet. The title bubble says "Offline".
- **05-assistant-offline**. The navigation-bar bubble shows "Offline" with no green dot. Above the composer, a single-line notice on a tinted strip: "Hermes is offline. Messages can't be delivered right now." The composer is enabled with the placeholder "Message".
- **06-assistant-list**. Title "Assistants". Rows of avatar (green dot while online), name, time at the right, and a one-line preview: "Hermes" (online) with the user's latest message "You: Thanks! Please also move my 2 pm meeting to 3." and "9:30 AM" (consistent with 01); "Grok Bot" (offline) with "You: Summarize today's news" and "Yesterday"; "Muse" (offline) with a red exclamation mark followed by "You: Are you there?" and "Mon"; and "Atlas" (purple avatar, a Link not yet connected) with "Assistant Link created" and "Oct 8". Previews are one line, truncated with an ellipsis.
- **07-conversation-dark**. Screen 01 in dark mode: dark background, the Assistant's bubble in dark grey, the user's bubble in the accent color, captions in secondary grey.

## Risks / Trade-offs

- [A lost receipt shows "Not Delivered" for a message the agent read] → Documented as at-least-once; the same `message_id` on retry lets agents drop duplicates.
- [No offline queue: a user whose Link is briefly offline must retry by hand] → Accepted for this slice; the queue is a later change, and "Try Again" is the manual form of it.
- [First online Link only: a broken first Link blocks messages while the second is fine] → Documented as an open question; both alternatives are additive.
- [The HTTP request is held for up to 10 seconds] → One short-lived request per sent message; the Task is supervised and the request has a deadline.
- [An agent never sees a message if it does not run `al wait` (or an equivalent connection)] → By design: the Link must be online. `install.md` already tells agents to keep `al wait` running; it also gains how to read events.

## Migration Plan

Additive. Deploy the service first: ALP and the client API only gain endpoints and a method, and agents that do not implement `message.deliver` just make messages fail. Then release `al` (so `al wait` can receive and `al send` can reply) and the app. Until an agent has the new `al`, the app shows "Not Delivered" for the user's messages, which is the correct state.

## Open Questions

See `proposal.md`. Beyond those, the agent-side `message.send` JSON-RPC method (for agents that hold a connection) and a failure reason in the message (to say why it failed) are left for later.
