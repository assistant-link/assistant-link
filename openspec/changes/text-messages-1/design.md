# Design

## Context

See `proposal.md` for the slice and `specs/` for the behavior. Today:

- The app derives "Assistant Link created" events from the Assistants list. The service stores no Timeline.
- `/alp/v1/connect` is a JSON-RPC 2.0 WebSocket with presence. The service sends only notifications.
- `/api/v1/connect` is the app's live connection.

## Decisions

### Log out: soft delete and purge
- Log out sets `accounts.deleted_at` and broadcasts `:account_deleted`.
- It deletes web sessions and magic links of users whose only account this is.
- Every account lookup requires `deleted_at IS NULL`: credentials, Link tokens, pairing, connect, the delivery query.
- A user's email stays taken until the purge (accepted).

`AssistantLink.Accounts.Purger` runs `Accounts.purge_deleted_accounts/0` hourly.
Per account, in one transaction:

1. Claim it with `FOR UPDATE SKIP LOCKED` once `deleted_at` is older than `:deletion_grace_period` (60 days).
2. Collect its member user ids.
3. Delete children first: `text_messages`, `assistant_events`, `pairing_codes`, `assistant_links`, `assistants`, `devices`, `memberships`, the account.
4. Delete each collected user with no membership left (`users_tokens`, then `users`), with or without an email.

### No cascades
No foreign key has an `ON DELETE` action, so a forgotten child fails loudly in the purge.
New keys have none. The seven existing cascades are replaced (`NOT VALID`, then `VALIDATE`).

### Events
One table, `assistant_events`. Payload in `text_messages(event_id primary key, text)`.

- `id` is a UUIDv7. `created_at` is `inserted_at`.
- `type`: `link_created` or `text_message`. `sender`: `user`, `assistant`, or `system`.
- `seq` is per Assistant, from `UPDATE assistants SET last_event_seq = last_event_seq + 1 … RETURNING` in the insert transaction.
- A deleted payload leaves a deleted event. This slice cannot delete one.
- A repeated idempotency key rolls back (undoing the `seq` bump) and returns the stored event: `200` or `409`, never `500`.
- `link_created` has sender `system`, is never delivered, and is backfilled for existing Links (UUIDv7 from the Link's creation time).

### Delivery
The service sends the event as the params of a JSON-RPC request, exactly the line `al wait` prints:

```json
{"jsonrpc": "2.0", "id": 7, "method": "event.deliver",
 "params": {"id": "0199…", "type": "text_message", "created_at": "2026-10-22T09:30:00Z", "deleted": false, "text_message": {"text": "Hi"}}}
```

A request, so the service can tell "taken" from "lost".

- Request ids are per-connection counters, never an event id.
- An old `al` answers `-32601`, so the event stays unacknowledged.
- `assistant_links.last_read_seq` (`bigint NOT NULL DEFAULT 0`) is the `seq` of the last event the Link acknowledged.
  Pairing sets it to `assistants.last_event_seq` without locking the Assistant row.
- Only the first ack by any Link sets `delivered_at` (`WHERE delivered_at IS NULL`).

One delivery process per online Link holds the event in flight and the retry timer.
It runs on connect, on an "event stored" PubSub notice, on each ack, and when the timer fires.
Its query: `seq > last_read_seq`, sender `user`, type `text_message`, lowest `seq`, limit 1.
`GET /alp/v1/link` counts the same query over HTTP, so no connection flickers the Link online.

### `al send` and `al wait`
- `al send` makes one HTTP attempt: a rerun after exit 5 may duplicate. Exit 4 now means any rejection.
- `al wait` prints JSON Lines in both modes; `--human` changes only stderr.
- One writer: write, flush, then ack. A repeat can only be the last event written.

### Security implications
- Message text reaches a model; the agent owns that trust boundary.
- Text stays in the clear until the purge and is not logged.
- Every Link of an Assistant receives its user messages, so create a Link only for a trusted agent.
- A leaked Link token can post as the Assistant, read from its cursor on, and set `delivered_at`.

### UI designs
`designs/` holds the mockups. If they disagree with the specs, the specs win.

![Overview](designs/overview.png)

## Risks / Trade-offs

- A lost ack redelivers; agents dedupe by `id`.
- A message typed before pairing never reaches that Link.

## Migration Plan

Additive. Deploy the service, then the app, then `al`.

- Add `accounts.deleted_at` with its index, `assistant_events`, `text_messages`, `assistants.last_event_seq`, `assistant_links.last_read_seq`.
- Backfill `link_created` per Link: `seq` per Assistant in `(inserted_at, id)` order, then `last_event_seq` = max `seq`. Existing Links start at `last_read_seq` 0.
- Replace the seven cascades; the rollback restores them.
- Forward-only: the previous service code must not run after this (its hard-delete log out fails on the foreign keys).
