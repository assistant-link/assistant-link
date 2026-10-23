# Proposal

## Why

The user and the Assistant cannot say anything to each other yet.
Text is the thinnest useful slice. Later event kinds reuse the same Timeline and delivery path.

An agent is often offline, and an Assistant may have several Links.
So the service stores each message and keeps it deliverable until a Link acknowledges it.

Serves V1 job **1. Reach my assistant from anywhere** and the first step of job **2. Let my assistant reach me**.

## What Changes

- **iOS app:** composer, message states, Timeline with paging, live updates, offline notice, latest event in the list.
- **Service:**
  - Stores every Timeline item as an event and serves history.
  - Delivers each user message in order to every Link, with one cursor per Link.
  - Rejects a message to an Assistant with no paired Link.
  - Log out becomes a soft delete. A periodic purge deletes after a grace period, with no database cascades.
- **ALP (additive):** `event.deliver`, `POST /alp/v1/messages`, `GET /alp/v1/link`.
- **`al`:** `al send`, `al wait` prints events, `al status` over HTTP, shorter `al help` and `install.md`.

## Non-goals

- Push notifications, retention limits, restoring an account, multi-device.
- Attachments, audio, other event types.
- Read state, typing indicators, editing or deleting messages, Markdown, search.
- Showing which Link received a message; delivering an agent's message to other Links.
- `al wait --since` and an agent-side `message.send`.

## Capabilities

- New: `messages`.
- Modified: `alp`, `agent-cli`, `assistants`, `app-account`.

## Open questions

Each was decided the simplest way. Change it before implementation if the product owner prefers.

1. Does a new Link receive older messages? No.
2. Does an agent's message reach other Links? No.
3. History size and text length? Latest 50; 4,000 code points.
4. How long does a deleted account's data stay? 60 days.

## Impact

- **Service:** new tables and columns, delivery and purge processes, the endpoints above.
- **Contracts:** ALP v1 (additive) and `al`.
- **App:** composer, bubbles, paging, live handlers.
- **Docs:** `docs/alp/v1.md`, `cli/README.md`, help texts, agent `install.md`.
