# Design

## Context

This change creates all three components: the iOS app, the service, and the `al` CLI. See `proposal.md` for motivation and `specs/` for the required behavior. Project-wide decisions this design builds on (stack, WebSocket end to end, OpenAI Realtime format for calls, principles) are recorded in `openspec/config.yaml` and `docs/`.

Two principles shape most choices here: use established protocols over invented ones, and keep the server doing as little work per connection as possible.

## Goals / Non-Goals

**Goals:**
- Three independently buildable components, each in its own repository (`backend`, `cli`, `apple`), a deployed service that work is verified against from early on, and the main `assistant-link` repository, which holds the local dev tooling (`scripts/clone`, `mise.toml`, `tests/integration/`) that runs all three together offline.
- A control connection that later slices (voice messages, calls) extend by adding JSON-RPC methods and notifications, not by changing the connection.
- Presence that costs the server close to nothing per idle agent.

**Non-Goals:**
- Horizontal scaling across several service nodes. One Fly machine is enough; the design should not block adding nodes later, but won't build for it.
- Production release automation for `al` beyond GitHub release binaries.

## Decisions

### Repository layout
Each component is its own repository in the `assistant-link` GitHub organization: `apple` (Xcode project, SwiftUI), `backend` (one Phoenix monolith serving the web pages, the client API, and ALP), `cli` (Rust crate `al`). Each builds and tests on its own, with its own CI and its own `mise.toml`. The main `assistant-link` repository ties them together.

*Alternative:* one repository holding all three components, the layout this change started with. We changed that to make it easy for each component to have its own release cadence.

### Service: full Phoenix monolith with a strict quality gate
The service is generated with all default `phx.new` options and stripped of Phoenix demo content, rather than as an API-only app. HTML, LiveView, assets, and mailer will be needed for later web use cases, and adding them to an API-only app later is harder than removing demo content now. Erlang and Elixir (and Rust, for the CLI) are pinned in the root `mise.toml`. `mix precommit` is the single quality gate (tools listed in `tasks.md` 2.2); dev/test-only tools never ship in the release.

*Alternative:* `phx.new --no-html --no-assets --no-live`. Rejected: smaller now, but costly to reverse.

### ALP control connection: plain WebSocket carrying JSON-RPC 2.0
`/alp/v1/connect` is a plain WebSocket (Bandit + `WebSock` handler), and every frame is one JSON-RPC 2.0 message.

*Why JSON-RPC 2.0?* Later slices need request/response on this connection: the agent sends a voice message and needs the new message id, or accepts a call and needs to know whether that worked. JSON-RPC defines id-based request/response pairing, notifications for events from the server, and a standard error object, so we don't invent our own. It is widely known to agents (MCP and LSP use it), and every language has a library or can implement it in a page of code.

*Why not Phoenix Channels?* Channels add their own framing (topics, refs, join/leave, heartbeats) that every third-party agent would have to implement.

*Why not `type`-tagged events (OpenAI Realtime style)?* They have no built-in request/response pairing or error convention; we'd be inventing both.

*Calls get their own socket.* The `live-calls` slice will open a separate per-call WebSocket (e.g. `/alp/v1/calls/<id>`) that carries pure OpenAI Realtime events, relayed untouched. The control connection only negotiates the call (`call.incoming` notification, `call.accept` request). Keeping media off the control socket lets the server relay audio without parsing it, lets `al call` and raw `websocat` pipes attach directly, and stops audio from delaying control messages. Nothing in this slice builds that; it is recorded here because it is why JSON-RPC on the control socket doesn't conflict with the Realtime format.

*Implementation:* no JSON-RPC framework on either side. The service has a small module (`AssistantLinkWeb.JSONRPC`) that decodes and validates messages and routes requests to a function per connection; an invalid request echoes its `id` when the `id` itself is valid, and a binary frame gets `-32600`. The CLI uses `serde` types for request, response, notification, and error. The message set is tiny and a framework (e.g. `jsonrpsee`) would add more than it saves.

The iOS app's live connection (`/api/v1/connect`) is part of the client API, not ALP. Like ALP's, it is one long-lived, two-way connection per client, under the same prefix as the REST endpoints it shares its credential and version with. It speaks JSON-RPC 2.0 like ALP, with the same message module and the same request/response and error conventions, because the app will also send requests over it; in this slice the service only sends the `link.status` notification. The app needs only `URLSessionWebSocketTask` and a small Codable layer.

### Presence: Phoenix.Presence, per-Link
Each agent WebSocket is one BEAM process. On connect it tracks itself with `Phoenix.Presence` (`AssistantLink.Presence`) under its `link_id` on its account's presence topic `links:<account_id>`; Presence monitors the process and untracks it when it exits (clean close, lost pong, or account deleted). The Presence `handle_metas/4` callback sees each Link's joins and leaves together with the connections that remain, and broadcasts `link.status` on the `Phoenix.PubSub` topic `account:<account_id>`: online when a Link's first connection joins, offline when its last one leaves. Every node runs `handle_metas/4` for every diff, so each node broadcasts only to its own subscribers. App sockets subscribe to their account topic and forward only these `link.status` events, never raw presence diffs.

Online/offline status lives only in memory (Presence) and is shared across nodes, so adding a second Fly machine needs no change. The only presence data written to Postgres is `last_active_at`: each agent connection process writes it when the connection opens and again when it closes, and keeps the time it wrote in its presence meta, so `link.status` carries exactly the stored time. That is two small writes per connection lifetime, and nothing while idle. The Presence process itself never touches the database, so a slow or failing database cannot block or crash presence tracking.

*Alternative:* a local `Registry` with our own monitors. Slightly less work per connection, but it sees only the node it runs on, and we would write the join/leave bookkeeping that Presence already provides.

### Liveness
The service pings every 25 s and closes the connection if nothing arrives within 60 s of a ping (per the `alp` spec). The connection process sends the pings; Bandit answers the client's pings and closes a connection that has sent no frame (pongs included) for 60 s, its WebSocket `timeout`. The app's live connection uses the same liveness, which also keeps an idle app connection open. Both intervals are configurable (`AssistantLinkWeb.Connection`), so tests use short ones.

### Tokens and codes (minimal, not hardened)
- **Account credential and Link token:** 32 random bytes, base64url, prefixed for recognizability (`ala_` for the account credential a device holds, `alt_` for Link token). Stored in Postgres as a SHA-256 hash only; the raw value is shown once.
- **Pairing code:** 8 characters from Crockford base32 (no I, L, O, U), stored hashed with `expires_at` and `used_at`. Displayed as `XXXX-XXXX`. Issued only for Links that are not paired yet. A submitted code is normalized before it is hashed: case, hyphens, and any whitespace (including line breaks and non-breaking spaces) are ignored, and the letters Crockford base32 leaves out are read as their look-alikes (O as 0, I and L as 1).
- **Pairing:** `POST /alp/v1/pair` with `{"code"}` → `200 {"link_id", "assistant_name", "token"}`. An unknown, replaced, or used code gets `422 invalid_code`, an unused code past its expiry `422 expired_code`, and a missing or non-string code `422 invalid_params`. Pairing locks the Link row, like issuing a code, so a code replaced or used concurrently is rejected.
- A Link token stays valid until its account is deleted; there is no per-Link revocation or re-pairing in this slice.
- Rate limiting, token rotation, revocation UI, and device attestation are left out (security hardening is out of scope). The trust boundaries are simple: the phone trusts the service; the service trusts whoever holds a valid token; the agent trusts the service URL it was given.

*Alternative for app identity:* Sign in with Apple. Better for multi-device and recovery, but adds setup (Apple Developer configuration, server-side token verification) and neither is needed yet.

### Identity and tenancy
The service keeps the person, the tenant, and the app install apart:

- **User** (the person): generated by `mix phx.gen.auth Accounts User users --binary-id`, so users, user tokens, and `AssistantLink.Accounts.Scope` follow Phoenix conventions. `email` is nullable: the app's users are anonymous. The generated web pages stay (registration, email and password or magic-link login, settings) under `/users/*`, and nothing links to them from `/`. Every way a user is created also creates their account and owner membership.
- **Account** (the tenant): owns Assistants and, through them, Links and pairing codes. It has no credential of its own, and always keeps at least one owner.
- **Membership:** joins a user to an account with a role. Registration creates one membership with role `owner`. A device acts in its own account; a web session acts in the account of the user's only membership and fails loudly if there is more than one.
- **Device** (the app install): holds the account credential the app sends as its bearer token, stored as a SHA-256 hash, plus `last_seen_at`, which is updated at most once a minute so authenticated requests rarely write. It is issued to one user acting in one account, so it records both, and it exists only while that membership does.

```
users --< memberships >-- accounts --< assistants --< assistant_links --< pairing_codes
  |           |
  |           +--< devices (token_hash)
  +--< users_tokens (phx.gen.auth)
```

`POST /api/v1/accounts` creates a user without email, an account, an owner membership, and a device for that membership in one transaction, and returns the device's credential once.

Each app request resolves its credential to a device and loads the device's user and account (the device exists only while their membership does), and builds `%Scope{user: user, account: account}` from that row. Only `AssistantLink.Accounts` builds scopes: from a device, or from a web session's user and their membership. The Phoenix scope config is keyed on the account (`access_path: [:account, :id]`, `schema_key: :account_id`), so contexts take the scope and filter by `scope.account.id`, and later `phx.gen.*` output does the same.

**Tenancy is enforced by the schema.** Every tenant-owned table carries `account_id`, so every query filters on it directly, without joining up to a parent. Each child references its parent through a composite foreign key that includes `account_id` (for example `assistant_links (account_id, assistant_id)` references `assistants (account_id, id)`), so a row can never point at another account's data.

### Data model (Postgres)
- `users`, `users_tokens`: as generated by `phx.gen.auth`, except `users.email` is nullable (its unique index still applies to non-null emails)
- `accounts(id, inserted_at)`
- `memberships(id, account_id, user_id, role, inserted_at)`, unique on `(account_id, user_id)`; `role` is `owner`
- `devices(id, account_id, user_id, token_hash, last_seen_at null, inserted_at)`, unique on `token_hash`; `(account_id, user_id)` references `memberships`
- `assistants(id, account_id, name, avatar, inserted_at)`, where `avatar` is a preset id `avatar-1` … `avatar-10`; unique on `(account_id, id)`
- `assistant_links(id, account_id, assistant_id, label null, token_hash null, paired_at null, last_active_at null, inserted_at)`; `(account_id, assistant_id)` references `assistants`; unique on `(account_id, id)` and on `token_hash`
- `pairing_codes(id, account_id, link_id, code_hash, expires_at, used_at null, inserted_at)`; `(account_id, link_id)` references `assistant_links`; unique on `code_hash`

IDs are monotonic UUIDv7, so ordering by id is creation order. Foreign keys use `ON DELETE CASCADE`: deleting an account removes its memberships, devices, Assistants, Links, and pairing codes; deleting a user removes their memberships, devices, and user tokens; deleting a membership removes its devices. A deferred constraint trigger requires every account to keep an owner at commit, so an account's only owner can be deleted only together with the account.

### Avatars
The service stores and validates only the preset id. The app maps each id to a filled circle in a fixed color (10 distinct colors, readable in light and dark mode). Swapping in final assets later is an app-only change; no data changes.

### App screens
The app follows the messaging-app pattern its later slices need (voice messages, calls). Home is a conversation list: each row shows the Assistant's avatar with a green dot while it is online, its name, its most recent event, and that event's time. Opening an Assistant shows its conversation screen, with a bubble in the navigation bar (avatar, name, status) that opens the Assistant's details: avatar, name, status, its Links with presence and last active time, adding a Link, and each unpaired Link's pairing text.

While an Assistant has no Links, its conversation screen is a short setup guide: one tap adds a Link and opens its pairing text to copy to the agent. "Add Link" in the details is one tap too. The app never asks for a label, so the path to a connection stays as short as possible; Links show a default name by position ("Link 1", "Link 2", …) until renaming exists. Once a Link exists, the screen shows the conversation, which in this slice holds only system events: "Assistant Link created" for each Link, shown as a centered caption, with a "Show pairing text" action while that Link is unpaired. There is no message bar until voice messages arrive.

The app derives these events from the Assistants list; the service stores no timeline yet. An event's time comes from its Link's id: ids are UUIDv7 (see Data model), whose leading 48 bits are the creation time in milliseconds. When a later slice stores the timeline in the service, its events replace these derived ones.

*Alternative:* add the Link's `inserted_at` to the client API. Cleaner, but it changes the API for a value the id already carries; it can be added together with the stored timeline.

### Log out
`DELETE /api/v1/account` deletes, in one transaction, the account (cascading to everything it owns) and every user whose only membership was in that account (cascading to their devices and user tokens), so the deleted account's credentials stop working. After commit, the service broadcasts on the account topic, and each agent connection and app connection for that account sends `connection.closing` with reason `account_deleted` and closes. The app shows two confirmations before calling it (a standard confirmation, then a destructive alert stating that everything is permanently deleted), then clears its Keychain credential and re-runs first launch.

### Client API
REST+JSON under `/api/v1`. Every endpoint except `POST /accounts`, which issues the credential, requires `Authorization: Bearer <account credential>`:
- `POST /accounts` → `201 {"account_id", "credential"}`
- `DELETE /account` → `204`
- `GET /assistants` → `{"assistants": [assistant]}`, oldest first, where an assistant is `{"id", "name", "avatar", "status", "links": [link]}` (`status` is `online` when any Link is) and a link is `{"id", "label", "status", "last_active_at"}` (`status` is `not_paired`, `online`, or `offline`; `label` and `last_active_at` may be `null`)
- `POST /assistants` with `{"name", "avatar"}` → `201 {"assistant": assistant}`
- `POST /assistants/:id/links` with an optional `{"label"}` → `201 {"link": link}`
- `GET /connect`: the app's live connection, a WebSocket (see the ALP control connection decision)
- `POST /links/:id/pairing_code` → `201 {"code", "expires_at", "pairing_text"}`; `409 already_paired` for a paired Link

Names and labels are trimmed and must be a single line (no control characters or line separators) of at most 50 characters; names also need at least one. Invalid input gets `422 invalid_params`, and an unknown id or another account's resource gets `404 not_found`. Issuing a pairing code locks the Link row, so concurrent requests leave exactly one unused code.

Errors here and in ALP share one body, `{"error": {"code": ..., "message": ...}}`, with a stable snake_case `code`. The endpoint's own JSON 404 and 500 responses use it too (`not_found`, `internal_server_error`). A missing or unknown bearer token gets `401` with `unauthorized`.

This is the API for our own clients (the iOS app in this slice), not part of ALP. It changes together with our clients, while ALP under `/alp/v1` is a public contract for third-party agents, versioned on its own. Each endpoint accepts only its own credential: `/api/v1` the account credential, ALP the Link token.

### Pairing text
Generated by the service (so the wording is consistent and updatable without an app release), returned with the pairing code, and shown verbatim in the app:

```
Connect to my assistant "Hermes" on Assistant Link.
Follow the instructions at https://<service>/install.md
Service: https://<service>
Pairing code: K7QM-2XPA (expires 14:32 UTC)
```

### CLI: Rust, small dependency set
`clap` (commands), `tokio` + `tokio-tungstenite` with rustls (WebSocket), `reqwest` with rustls (pairing), `serde`/`serde_json`. rustls avoids a system OpenSSL dependency so Linux builds can be fully static (musl). Both trust the OS certificate store (reqwest's default rustls setup and tokio-tungstenite's `rustls-tls-native-roots`), so a minimal Linux host needs its CA bundle to connect; bundling `webpki-roots` instead is a contained change if that becomes a problem.

Link key: `al` keeps no state on the host. The Link key is the Link token as the service issues it; the agent stores it wherever suits its host and supplies it on every run, so one host user can hold any number of Links. `al status` and `al wait` read it from `--key-file <path>`, else `AL_LINK_KEY`, trimming surrounding whitespace; there is no flag taking the key itself, because command-line arguments show up in `ps` and shell history. `al pair` prints the key as `link_key`, or with `--key-file <path>` writes it to a new `0600` file and leaves it out of the output; it refuses an existing path before sending the code, so a typo cannot overwrite another Link's key or consume the code. Every command uses the service given by `--server`, else `AL_SERVER`, else the production URL; `al` does not bind a key to the service that issued it.

`al wait` reconnect: exponential backoff from 1 s to a 30 s cap, with jitter; reset after a connection stays up for 60 s. It retries network errors, `5xx` responses, and dropped connections forever. It stops on `401` or `account_deleted` (exit 4), and on any other `4xx` at the upgrade (exit 1), because retrying cannot fix a wrong service URL. It also treats a connection that has sent no frame for 60 s as lost, since the service pings every 25 s and a half-open TCP connection would otherwise never end. On SIGINT or SIGTERM it closes the connection within 2 s, letting an upgrade still in flight finish so it can be closed too; a second signal exits at once.

### CLI output: JSON by default
`al`'s main users are agents, so every command prints JSON by default and `--human` prints text instead. Clap's usage errors (exit 2) stay as text on standard error. The exit code always signals the outcome, in either format.

- `al pair` prints one object on standard output: `{"server", "link_id", "assistant_name", "link_key"?}` (`link_key` left out with `--key-file`), or `{"error": {"code", "message"}}` on failure.
- `al status` prints one object on standard output: `{"server", "link_id"?, "assistant_name"?, "check", "error"?}`, where `check` is `accepted`, `rejected`, `unreachable`, `no_key`, or `unexpected` (exit 1). `check` names the result of this one check: `al status` closes the connection right after `connection.ready`, so it never leaves the Link online. `link_id` and `assistant_name` come from `connection.ready`, so they are present only when the check is `accepted`.
- `al wait` keeps standard output for events and writes status as JSON lines on standard error: `{"status": "connected", "server", "link_id", "assistant_name"}`, `{"status": "reconnecting", "delay_ms", "error"}`, and a final `{"status": "stopped", "error"?}`.

Error codes are the service's own (`invalid_code`, `expired_code`, `invalid_params`, `unauthorized`) or `al`'s: `no_key`, `key_file_exists`, `unreachable` (could not connect), `connection_lost` (an open connection dropped), `account_deleted`, `unexpected`.

### Impact on the agent-facing interface
This change fixes the parts of the public contract that are hardest to change later:
- the `/alp/v1` path and bearer-token auth;
- JSON-RPC 2.0 on the control connection, including the `-32000..-32099` range with `data.reason` for ALP errors;
- the `connection.ready` and `connection.closing` notifications;
- the rule to ignore unknown notifications and fields;
- `al`'s exit codes, its JSON output (including the `check` values and error codes), and the rule that standard output is for events.

Later slices add methods and notifications (`message.*`, `call.*`), a per-call media socket, and `al` subcommands, without changing these.

### install.md
Served by the service as a static file at `/install.md` (versioned in `backend/priv/static/`). It follows the structure of OpenSpec's `install.md`: objective, done-when checks, ordered steps, stop conditions. For this slice it installs `al` from GitHub release binaries by platform, with `cargo install --git` as a fallback. Each release asset is `al-<target>.tar.gz`, a tarball holding the `al` binary, where `<target>` is the Rust target triple (`aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl`), so `install.md` can download it from `releases/latest/download/`. It sets `AL_SERVER` only when the pairing text names a service other than production. It pairs with `al pair --key-file`, so the key never appears in the agent's tool output, then shows how to move the key into the host's secret storage and run `al wait` from a small wrapper that supplies `AL_LINK_KEY`, with examples for the macOS Keychain (`security`), the Linux Secret Service (`secret-tool`), and a key file readable only by the agent's user as a fallback. An agent running several assistants on one host keeps one key per assistant.

## Risks / Trade-offs

- [Anonymous per-install account: deleting the app loses access to its Assistants] → Acceptable for the reference user.
- [Log out is permanent and immediate] → Two confirmations, the second one destructive-styled and explicit about what gets deleted.
- [Presence lives only in memory: a restart or redeploy shows everything offline until agents reconnect] → `al wait` reconnects automatically with backoff; agents are back within ~30 s. `last_active_at` in Postgres survives restarts.
- [A leaked Link token stays valid until the account is deleted, with no per-Link revocation] → Acceptable while hardening is out of scope.
- [`al` does not bind a Link key to the service that issued it, so a wrong `AL_SERVER` sends the key to another service] → `install.md` takes the service only from the pairing text, and a rejected key is reported with the service URL that was used.
- [The Link key can end up in the agent's transcript, which may be logged or sent to a model provider] → `install.md` pairs with `--key-file`; `al pair` prints the key only when no key file is given.
- [Hand-written JSON-RPC handling instead of a library] → The message set is tiny and covered by tests against the error cases in the `alp` spec.

## Migration Plan

Greenfield; nothing to migrate. `al` binaries are published once the CLI exists, and the app is installed via Xcode/TestFlight.

## Open Questions

- Final avatar assets (app-only change when ready).
- Renaming Links, in a later slice: it needs a client API endpoint (for example `PATCH /api/v1/links/:id`). `POST /assistants/:id/links` keeps its optional label, which the app does not send.
