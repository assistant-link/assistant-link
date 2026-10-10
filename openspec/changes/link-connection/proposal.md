# Proposal

## Why

Nothing exists yet: there is no app, no service, and no way for an agent to connect. Every MVP use case (voice messages, live calls) depends on the same foundation: a user has Assistants in the app, each Assistant has Assistant Links, and the agent behind a Link can authenticate and connect. This first vertical slice builds that foundation end to end across all three components, so later slices only add methods and notifications on top of a working connection.

Serves V1 job **1. Reach my assistant from anywhere**. It establishes the path the user will later use to reach the agent.

## What Changes

- **iOS app (new, SwiftUI):**
  - On first launch the app registers itself with the service and shows the user's Assistants, like a messaging app's conversation list, with their connection status.
  - The user can create an Assistant (a name and one of 10 preset avatars) and create Assistant Links for it.
  - For each new Link, the user can copy paste-to-agent pairing text that contains a short-lived pairing code.
  - Opening an Assistant shows its conversation screen, headed by the Assistant's name, avatar, and status; until it has an Assistant Link the screen guides the user to create one, and afterwards it shows a system event for each Link created. The Assistant's details list all of its Links, each with its label, presence (online/offline), and when it was last active. Status updates live.
  - The user can log out. This deletes the account and all of its data on the server, after two confirmations.
- **Service (new, Elixir/Phoenix + Postgres):**
  - Stores users (anonymous for now), accounts with their memberships, the app's devices, Assistants, and Assistant Links.
  - Issues pairing codes and exchanges a valid code for a long-lived Link token.
  - Accepts agent WebSocket connections authenticated by that token, tracks Link presence and last active time, and publishes presence to the app over WebSocket.
  - Deletes an account and everything it owns on request.
  - Serves the agent-facing `install.md`.
- **Assistant Link Protocol, v1 foundation (new):** This slice defines the versioned public API agents use:
  - an HTTP endpoint to pair;
  - an agent WebSocket that speaks JSON-RPC 2.0.

  It sets the conventions later slices extend: versioning, bearer-token auth, JSON-RPC methods and notifications, and error shape.
- **Agent CLI `al` (new, Rust):** A single self-contained binary with three commands:
  - `al pair <code>`: exchanges the code for a Link token and stores it locally.
  - `al status`: reports pairing and whether the service accepts the connection.
  - `al wait`: holds the connection open, so the Link is online, until interrupted. In later slices, it also returns incoming messages and calls.
- **Paste-to-agent onboarding:** The pairing text points the agent at an `install.md` that walks it through installing `al`, pairing, and verifying. The approach follows the pattern of OpenSpec's `install.md`.

## Non-goals

- Voice messages, live calls, and a stored timeline. These come in later slices, including the separate per-call media WebSocket. This slice's conversation screen shows only system events the app derives from the Assistant's Links.
- Push notifications, an agent-side background service, and security hardening.
- Sign-in from the iOS app, multi-device sync, or account recovery. The app's user is anonymous and tied to the app install.
- Photo or custom avatars. The 10 presets are placeholders (colored circles) until final assets are defined.
- Routing between several Links of one Assistant.
- Holding more than one Link on a single agent host (a known gap, see `design.md`).
- Editing or deleting individual Assistants and Links (including renaming; the app creates Links without labels), and revoking or re-pairing individual Links.
- A published release pipeline for `al` (Homebrew, installer script). Building from source and GitHub release binaries are enough for this slice.

## Capabilities

### New Capabilities

- `app-account`: how the iOS app gets an identity with the service (anonymous, per-install account), authenticates its requests, and logs out by deleting the account and all its data.
- `assistants`: creating and listing Assistants (name, preset avatar) and showing their connection status in the app.
- `assistant-links`: creating Assistant Links, issuing paste-to-agent pairing text with a short-lived pairing code, exchanging the code for a Link token, and showing each Link's presence and last active time.
- `alp`: the public, versioned Assistant Link Protocol contract for agents: the pairing endpoint, the JSON-RPC 2.0 agent WebSocket, authentication, versioning, and errors.
- `agent-cli`: the `al` command-line tool's observable behavior: `pair`, `status`, `wait`, local credential storage, and exit codes.

### Modified Capabilities

(none; no existing specs)

## Impact

- **New code:** `ios/` (SwiftUI app), `backend/` (Phoenix monolith, Postgres schema and migrations), `cli/` (Rust crate), and a root `mise.toml` pinning Erlang, Elixir, and Rust.
- **New public contract:** ALP v1 endpoints under a versioned path. Third-party agents depend on this, so changes to it are compatibility-sensitive from now on.
- **Dependencies:** Phoenix/Ecto/Bandit and `bcrypt_elixir` (added by `phx.gen.auth`) (service), plus dev/test-only quality tools (Credo, ex_slop, Styler, Sobelow, mix_audit, ExDNA, excellent_migrations, Boundary, Tidewave); `clap`, `tokio`, `tokio-tungstenite`, `reqwest`, `serde` (CLI); no third-party iOS dependencies.
