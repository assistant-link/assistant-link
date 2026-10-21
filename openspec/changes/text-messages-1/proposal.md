# Proposal

## Why

The app, the service, and the agent connection exist, but the user and the Assistant cannot say anything to each other yet: the conversation screen holds only "Assistant Link created" events. Text is the simplest thing that makes the connection useful, and every later kind of event (calls, audio, requests, push notifications) builds on the same Timeline, delivery path, and `al` events. This slice is the thinnest end-to-end version: the user and the Assistant can text each other.

An agent is often not connected when the user writes, and an Assistant may have several Assistant Links. So the service stores what the user sends and keeps it available for delivery for 7 days (the *delivery retention*): every Assistant Link of the Assistant receives the messages, each remembers where it left off, and a Link that was offline catches up when it connects.

Serves V1 job **1. Reach my assistant from anywhere**, and the first step of job **2. Let my assistant reach me**: the Assistant can message the user while the app is open.

## What Changes

- **iOS app:**
  - The conversation screen gets a composer. A sent message shows "Sending…" while the app waits for the service, "Sent" once the service stored it, and "Delivered" once an Assistant Link acknowledged it. "Not Delivered" appears only for a real failure: the service rejected the message or could not be reached ("Try Again"), or no Assistant Link took it within the delivery retention.
  - The Timeline mixes messages with the existing "Assistant Link created" events. History persists; the app loads the latest 50 and offers "Load Earlier Messages".
  - The Assistant's messages and changes to the state of the user's messages appear live while the app is open. While the Assistant is offline, a notice above the composer says messages will be delivered when it connects.
  - Each Assistant list row shows the latest message ("You: …" for the user's own) as its most recent event.
- **Service:**
  - Stores messages per Assistant until the account is deleted, and serves history.
  - Keeps each message of the user available to Assistant Links for the delivery retention (7 days) and delivers it, in order, to every Assistant Link of the Assistant, tracking one read position (cursor) per Link. A Link that connects later catches up on what it missed within the retention.
  - Accepts messages from the agent and pushes them to the app's live connection.
- **ALP (additive within `/alp/v1`):**
  - `event.deliver`: a JSON-RPC *request* from the service to the agent whose params are the event (`{"id", "type": "message", "text", "sent_at"}`). The agent's response acknowledges it and advances that Link's cursor.
  - `POST /alp/v1/messages`: the agent sends a message to the user.
- **`al`:**
  - `al send`: sends a message from the agent to the user.
  - `al wait` writes each incoming event to standard output as one JSON object per line, and acknowledges it after the line is written. This defines the event format that later event types extend.

## Non-goals

- Push notifications (later work). An Assistant's message reaches the user only while the app is open or the next time the user opens it.
- Keeping messages available for delivery for longer than 7 days, or expiring the Timeline: the history stays until the account is deleted.
- Attachments, images, and audio (later work), and event types other than messages. The per-Link stream is built for them, but this slice defines only `message`.
- Rate limiting and request size limits beyond the 4,000 character limit (left for security hardening).
- A "Read" state, typing indicators, unread badges, editing or deleting messages, notification actions, Markdown rendering, and search.
- Showing in the app which Assistant Link received a message: "Delivered" means at least one did.
- Delivering a message the agent sends on one Assistant Link to the Assistant's other Links.
- An agent choosing its own start position in the stream (for example `al wait --since <id>`). The service keeps the cursor.

## Capabilities

### New Capabilities

- `messages`: sending, storing, delivering, and showing text messages in the Timeline, including the delivery retention, the per-Link cursor and catch-up, the message states, and message history.

### Modified Capabilities

- `alp`: adds the `event.deliver` request, its acknowledgement and error rules, and the `POST /alp/v1/messages` endpoint, and notes that a service-to-agent event that needs an acknowledgement is a request.
- `agent-cli`: adds `al send` and the incoming-event format of `al wait`, and extends the output, key input, and exit-code requirements to `al send`.
- `assistants`: the Assistant list's most recent event and the conversation screen include messages.
- `app-account`: deleting the account deletes messages.

## Open questions

Each was decided here by choosing the simplest option that fits the existing specs; change it before implementation if the product owner prefers another.

1. **Does the Timeline expire like the delivery retention?** Chosen: no. The Timeline keeps messages until the account is deleted, so history survives relaunch; the 7 days only bound what an Assistant Link can still receive. Alternative: delete messages after 7 days.
2. **Does a newly paired Assistant Link receive older messages?** Chosen: no, its cursor starts at its pairing time. Alternative: start at the Link's creation, or at the oldest message within the retention.
3. **Can the user retry a message that expired undelivered?** Chosen: no, it is final ("Not Delivered" without "Try Again"); the user can type it again. Alternative: re-post it with a new retention window.
4. **Does a message an agent sends on one Assistant Link reach the Assistant's other Links?** Chosen: no, not in this slice. Alternative: deliver it to them as an event of another `type`.
5. **How much history does the app load, and how long may a text be?** Chosen: the latest 50 messages with "Load Earlier Messages", and 4,000 Unicode code points.

## Impact

- **Service:** a `messages` table, `assistant_links.delivered_through`, a delivery process per online Link, a retention setting (default 7 days), and the endpoints above.
- **Public contracts:** ALP v1 (additive) and `al` (one new command, the stdout event format of `al wait`). An agent that does not implement `event.deliver` leaves the user's messages undelivered, not the connection broken.
- **App:** a composer, message bubbles, history paging, and live notification handlers.
- **Docs:** `docs/alp/v1.md` in the backend repository, `cli/README.md`, and the agent `install.md`.
