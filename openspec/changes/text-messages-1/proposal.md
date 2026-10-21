# Proposal

## Why

The app, the service, and the agent connection exist, but the user and the Assistant cannot say anything to each other yet: the conversation screen holds only "Assistant Link created" events. Text is the simplest thing that makes the connection useful, and every later kind of message (push notifications, voice, images) builds on the same Timeline, delivery path, and `al` events. This slice is the thinnest end-to-end version: the user and the Assistant can text each other.

Serves V1 job **1. Reach my assistant from anywhere**, and the first step of job **2. Let my assistant reach me**: the Assistant can message the user while the app is open.

## What Changes

- **iOS app:**
  - The conversation screen gets a composer. A sent message shows "Sending…", then "Sent", or "Not Delivered" with "Try Again" when the Assistant's Assistant Link was offline or did not confirm.
  - The Timeline mixes messages with the existing "Assistant Link created" events. History persists; the app loads the latest 50 and offers "Load Earlier Messages".
  - The Assistant's messages appear live while the app is open. While it is offline, a notice above the composer says so.
  - Each Assistant list row shows the latest message ("You: …" for the user's own) as its most recent event.
- **Service:**
  - Stores messages per Assistant (they are deleted with the account) and serves history.
  - Delivers a user's message to one connected Assistant Link and records `sent` or `failed` from the agent's receipt.
  - Accepts messages from the agent and pushes them to the app's live connection.
- **ALP (additive within `/alp/v1`):**
  - `message.deliver`: a JSON-RPC *request* from the service to the agent. The agent's response is the receipt.
  - `POST /alp/v1/messages`: the agent sends a message to the user.
- **`al`:**
  - `al send`: sends a message from the agent to the user.
  - `al wait` now writes each incoming message to standard output as one JSON object per line, and acknowledges it after the line is written. This defines the event format that later event types extend.

## Non-goals

- Push notifications (later work). An Assistant's message reaches the user only while the app is open or the next time the user opens it.
- An offline queue and delivery after the Link reconnects. A message that fails is never delivered later on its own.
- Attachments, images, and audio (later work).
- Rate limiting and request size limits beyond the 4,000 character limit (left for security hardening).
- Read receipts, typing indicators, unread badges, editing or deleting messages, notification actions, Markdown rendering, and search.
- Choosing the Link a message goes to. The service picks one (see `design.md`).
- Multi-device sync of a user's own message state. The app that sends a message learns its state from the service's response.

## Capabilities

### New Capabilities

- `messages`: sending, delivering, storing, and showing text messages in the Timeline, including the sent and failed states and message history.

### Modified Capabilities

- `alp`: adds the `message.deliver` request and the `POST /alp/v1/messages` endpoint, and notes that a service-to-agent event that needs a receipt is a request.
- `agent-cli`: adds `al send` and the incoming-event format of `al wait`, and extends the output, key input, and exit-code requirements to `al send`.
- `assistants`: the Assistant list's most recent event and the conversation screen include messages.
- `app-account`: deleting the account deletes messages.

## Open questions

Each was decided here by choosing the simplest option that fits the existing specs; change it before implementation if the product owner prefers another.

1. **Which Link gets a message when several are online?** Chosen: the online Link that comes first in creation order ("Link 1" before "Link 2"). No fallback to another Link if it fails.
2. **What does the composer do while the Assistant is offline?** Chosen: it stays enabled and a notice sits above it; a message sent then is marked "Not Delivered" at once. Alternative: disable sending.
3. **Can the user retry a failed message?** Chosen: yes, tapping it offers "Try Again", which re-sends the same message in its place.
4. **How much history does the app load?** Chosen: the latest 50 messages, with "Load Earlier Messages" at the top.
5. **How long may a text be, and how long may delivery take?** Chosen: 4,000 Unicode code points, and 10 seconds without a receipt means failed.
6. **Does the Assistant list preview a failed message?** Chosen: yes, like any other, with a red exclamation mark.

## Impact

- **Service:** a `messages` table, client API endpoints under `/api/v1`, `POST /alp/v1/messages`, and a `message.deliver` request on the agent connection.
- **Public contracts:** ALP v1 (additive: one request method, one endpoint, one error reason) and `al` (one new command, the stdout event format of `al wait`). Older agents keep working; an agent that does not implement `message.deliver` makes the user's message fail, not the connection.
- **App:** a composer, message bubbles, history paging, and a live notification handler.
- **Docs:** `docs/alp/v1.md` in the backend repository, `cli/README.md`, and the agent `install.md`.
