# Tasks

## 1. backend: storage and client API

- [x] 1.1 Migration: events, payloads, cursors, `link_created` backfill; verify migrate, rollback, backfill order
- [x] 1.2 Text validation; verify empty, whitespace, 4,000/4,001, NUL
- [x] 1.3 `link_created` with the Link, events endpoint, `latest_event`; verify paging, deleted payload, `404`
- [x] 1.4 `POST /api/v1/assistants/:id/messages` with `no_paired_link`; verify check order, repeat, conflict
- [x] 1.5 `delivered_at` first-write-wins, `event.updated`; verify one `event.updated`
- [x] 1.6 `event.created` on the app connection; verify account isolation
- [x] 1.7 Migration for `accounts.deleted_at`; verify existing accounts stay null
- [x] 1.8 Soft-delete log out; verify data stays and connections close with `account_deleted`
- [x] 1.9 Exclude deleted accounts from lookups, pairing, connect, delivery; verify each is rejected
- [x] 1.10 `:deletion_grace_period`; verify the default
- [x] 1.11 `Accounts.purge_deleted_accounts/0` and `Purger`; verify full purge, other accounts and shared users kept
- [x] 1.12 Migration replacing the seven cascades; verify no `ON DELETE` action remains

## 2. backend: ALP and delivery

- [x] 2.1 Per-Link delivery and `event.deliver`; verify ack, error, `-32601`, `-32001`, timeout, backoff
- [x] 2.2 Pairing sets `last_read_seq`; verify before/after pairing, two Links, catch-up
- [x] 2.3 `POST /alp/v1/messages`; verify responses, repeat, conflict, no presence change
- [x] 2.4 `GET /alp/v1/link`; verify count, nothing moves, `401`
- [x] 2.5 Update `docs/alp/v1.md`; verify examples against a running service
- [x] 2.6 Trim the agent `install.md`; verify every command works

## 3. cli

- [x] 3.1 `al wait` events and acknowledgement; verify against a mock server incl. SIGINT
- [x] 3.2 `al send`; verify key, one attempt, exit codes
- [x] 3.3 `al status` over `GET /alp/v1/link`; verify each `check` value, no WebSocket
- [x] 3.4 Help texts with the OS-specific Link key section; verify per OS
- [x] 3.5 Update `cli/README.md`; verify each command runs

## 4. apple

- [x] 4.1 Event model, API calls, live handlers, refetch; verify with a stubbed `URLProtocol` and fake socket
- [x] 4.2 Timeline, deleted bubble, "Load Earlier Messages"; verify with previews and paging tests
- [x] 4.3 Composer, message states, "Try Again"/"Cancel"; verify with state tests
- [x] 4.4 Composer only with a paired Link, offline notice; verify in the Simulator
- [x] 4.5 Assistants list preview; verify with previews and tests
- [x] 4.6 Compare with `designs/` in light and dark; verify with screenshots

## 5. Integration tests (this repository)

- [x] 5.1 Pair, `al wait`, send from the app API; assert the stdout line and `delivered`
- [x] 5.2 Two messages before `al wait`; assert both in order, no repeat after a restart
- [x] 5.3 Two Links: each gets every message, a later Link nothing older
- [x] 5.4 Unread stdout gets `not_received`; `al send` reaches the app
- [x] 5.5 Account deletion with a short grace period: unreachable, rows gone after the purge
- [x] 5.6 `al status` during `al wait` disturbs nothing; `no_paired_link` until pairing

Verify each with `mise run test:integration`.

## 6. End-to-end verification

- [ ] 6.1 Physical iPhone against a deployed service: "Sent" then "Delivered", `al send`, offline notice
- [ ] 6.2 Airplane mode and "Try Again"; log out then purge
