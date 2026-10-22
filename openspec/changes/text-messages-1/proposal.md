# Proposal

## Why

The app, the service, and the agent connection exist, but the user and the Assistant cannot say anything to each other yet: the conversation screen holds only "Assistant Link created" events. Text is the simplest thing that makes the connection useful, and every later kind of event (calls, audio, requests, push notifications) builds on the same Timeline, delivery path, and `al` events. This slice is the thinnest end-to-end version: the user and the Assistant can text each other.

An agent is often not connected when the user writes, and an Assistant may have several Assistant Links. So the service stores what the user sends and keeps it available for delivery for 7 days (the *delivery retention*): every Assistant Link of the Assistant receives the messages, each remembers where it left off, and a Link that was offline catches up when it connects.

Serves V1 job **1. Reach my assistant from anywhere**, and the first step of job **2. Let my assistant reach me**: the Assistant can message the user while the app is open.

## What Changes

- **iOS app:**
  - The conversation screen gets a composer. A sent message shows "Sending…" until the service answers the post (no timer of the app's own), "Sent" once the service stored it, and "Delivered" once an Assistant Link acknowledged it. "Not Delivered" appears only for a real failure: the service answered with an error or the network failed ("Try Again"), or no Assistant Link took it within the delivery retention (derived when the message is read, not stored).
  - The Timeline mixes messages with "Assistant Link created" events, which now come from the service as part of the history instead of being derived by the app. History persists; the app loads the latest 50 and offers "Load Earlier Messages".
  - The Assistant's messages and changes to the state of the user's messages appear live while the app is open. While the Assistant is offline, a notice above the composer says messages will be delivered when it connects.
  - Each Assistant list row shows the latest message ("You: …" for the user's own) as its most recent event.
- **Service:**
  - Stores every item of an Assistant's Timeline as an event until the account is purged, and serves history. "Assistant Link created" becomes a stored `link_created` event, written when the Link is created and backfilled for existing Links.
  - Keeps each message of the user available to Assistant Links for the delivery retention (7 days) and delivers it, in order, to every Assistant Link of the Assistant, tracking one read position (cursor) per Link. A Link that connects later catches up on what it missed within the retention.
  - Accepts messages from the agent and pushes them to the app's live connection.
  - Log out becomes a soft delete: it sets `accounts.deleted_at`, the account behaves as deleted at once (credentials and Link tokens rejected, connections closed), and a periodic purge permanently deletes it, with its messages and everything else it owns, once the deletion grace period (default 60 days) has passed.
- **ALP (additive within `/alp/v1`):**
  - `event.deliver`: a JSON-RPC *request* from the service to the agent whose params are the event (`{"id", "type": "text_message", "created_at", "deleted", "text_message": {"text"}}`: the common fields plus the content nested under the type). The agent's response acknowledges it and advances that Link's cursor.
  - `POST /alp/v1/messages`: the agent sends a message to the user; it answers `{message_id, created_at}`. `idempotency_key` is a UUIDv7 string, required from the app and optional from the agent.
- **`al`:**
  - `al send`: sends a message from the agent to the user, with a fresh UUIDv7 `idempotency_key` per invocation and one attempt.
  - `al wait` writes each incoming event to standard output as one JSON object per line through a single writer that never interleaves, acknowledges it after the line is written, and drops a repeat of the last event. This defines the event format that later event types extend. A deleted message is delivered as an event with `"deleted": true`.
  - `al help` is short and general; `al wait --help` and `al send --help` hold the details. The usage moves there from the agent `install.md`, which keeps only installing, pairing, the Link key, and verifying, and ends with "Run `al help` and follow it".

## Non-goals

- Push notifications (later work). An Assistant's message reaches the user only while the app is open or the next time the user opens it.
- Keeping messages available for delivery for longer than 7 days, or expiring or deleting any part of the Timeline: the history stays until the account is purged.
- Restoring a deleted account: the app removes its only credential on log out, so the user cannot come back.
- Multi-device: reading the same Timeline from additional app devices of the account.
- Attachments, images, and audio (later work), and event types other than `text_message` and `link_created`. The per-Link stream is built for them, but this slice delivers only `text_message`.
- Rate limiting and request size limits beyond the 4,000 character limit (left for security hardening).
- A "Read" state, typing indicators, unread badges, editing or deleting messages, notification actions, Markdown rendering, and search.
- Showing in the app which Assistant Link received a message: "Delivered" means at least one did.
- Delivering a message the agent sends on one Assistant Link to the Assistant's other Links.
- An agent choosing its own start position (for example `al wait --since <id>`), an agent-side `message.send` JSON-RPC method, and a failure reason in the message.

## Capabilities

### New Capabilities

- `messages`: the Timeline of events (text messages and Link-created events) and the sending, storing, delivering, and showing of text messages in it.

### Modified Capabilities

- `alp`: adds the `event.deliver` request, its acknowledgement and error rules, and the `POST /alp/v1/messages` endpoint, and notes that a service-to-agent event that needs an acknowledgement is a request.
- `agent-cli`: adds `al send`, `al help`, and the incoming-event format of `al wait`, modifies the install instructions, and extends the output, key input, and exit-code requirements to `al send`.
- `assistants`: the Assistant list's most recent event and the conversation screen include messages.
- `app-account`: log out soft deletes the account (`deleted_at`), its data, including messages, is unreachable at once and permanently erased after the deletion grace period (default 60 days), one account per purge transaction, and each user left with no account is deleted; the log-out confirmation copy is unchanged.

## Open questions

Each was decided here by choosing the simplest option that fits the existing specs; change it before implementation if the product owner prefers another.

1. **Does the Timeline expire like the delivery retention?** Chosen: no. The 7 days only bound what an Assistant Link can still receive. Alternative: delete messages after 7 days.
2. **Does a newly paired Assistant Link receive older messages?** Chosen: no, its cursor starts at the Assistant's last event sequence when it is paired (no lock; a message sent at the same moment may arrive either way). Alternative: start at the Link's creation, or at the oldest message within the retention.
3. **Can the user retry a message that went undelivered past the retention?** Chosen: no, it is final ("Not Delivered" without "Try Again"); the user can type it again. Alternative: re-post it with a new retention window.
4. **Does a message an agent sends on one Assistant Link reach the Assistant's other Links?** Chosen: no, not in this slice. Alternative: deliver it to them as an event of another `type`.
5. **How much history does the app load, and how long may a text be?** Chosen: the latest 50 messages with "Load Earlier Messages", and 4,000 Unicode code points.
6. **How long does a deleted account's data stay?** Chosen: 60 days (the deletion grace period, one setting). Alternative: another period, or no grace period as before.
7. **How often does the purge run, and are device rows deleted at log out?** Chosen: hourly, and device rows are kept until the purge (the `deleted_at` check rejects them), so log out is one UPDATE plus the deletion of the web tokens of users whose only account it is. Their email stays taken until the purge: accepted; anonymous app users have no email. Alternative: delete devices at log out.

## Impact

- **Service:** the `assistant_events` and `text_messages` tables (with a backfill of `link_created` events for existing Links), `assistants.last_event_seq`, `assistant_links.last_read_seq` (`bigint NOT NULL DEFAULT 0`), a delivery process per online Link, a retention setting (default 7 days), `accounts.deleted_at` with a deletion grace period setting (default 60 days) and a supervised purge process, and the endpoints above.
- **Public contracts:** ALP v1 (additive) and `al` (the new commands `al send` and `al help`, the stdout event format of `al wait`). An agent that does not implement `event.deliver` leaves the user's messages undelivered, not the connection broken.
- **App:** a composer, message bubbles, history paging (which now includes Link events), and live notification handlers; it no longer derives "Assistant Link created" events.
- **Docs:** `docs/alp/v1.md` in the backend repository, `cli/README.md`, the `al` help texts, and the agent `install.md` (trimmed to installing, pairing, the Link key, and verifying).
