# Getting started

This guide sets up a workspace with every Assistant Link component and runs them together on your machine.

## Prerequisites

- [Git](https://git-scm.com) and [mise](https://mise.jdx.dev). mise installs the pinned versions of every other tool
  the components need ([`mise.toml`](../mise.toml)): Erlang and Elixir for the service, Rust for `al`, and XcodeGen
  for the iOS app (on macOS only).
- PostgreSQL 18 on `localhost:5432`, accepting the user `postgres` with password `postgres`, for the service. On macOS,
  [Postgres.app](https://postgresapp.com) works as is. Anywhere with Docker:

  ```sh
  docker run -d --name assistant-link-postgres -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:18
  ```

- For the iOS app only: macOS with Xcode 16 or later and an iOS 18+ Simulator runtime, and `jq` (preinstalled on
  macOS 15 and later).
- `curl` and `jq`, for the integration tests.

You only need the prerequisites of the components you work on. For example, `al` builds on Linux with just mise.

## Clone the workspace

```sh
git clone https://github.com/assistant-link/assistant-link.git
cd assistant-link
mise trust
mise install
mise run clone
```

`mise run clone` runs [`scripts/clone`](../scripts/clone), which clones the component repositories into
[`components/`](../components/):

```
assistant-link/          this repository
└── components/
    ├── backend/         github.com/assistant-link/backend
    ├── cli/             github.com/assistant-link/cli
    └── apple/           github.com/assistant-link/apple
```

Each component is its own git repository, ignored by this one. See [how to make changes](engineering/how-to-make-changes.md).
The script is safe to run again at any time. It clones only what is missing, leaves existing checkouts alone, and
prints what it did:

```
backend: cloned https://github.com/assistant-link/backend.git
cli: already cloned, left alone
apple: cloned https://github.com/assistant-link/apple.git
```

Every component tracks its `main` branch. To work from your forks, or to clone over SSH, set where the repositories
come from:

```sh
ASSISTANT_LINK_GIT_BASE=git@github.com:your-user mise run clone
```

Each component's own `mise.toml` pins the same versions as this one, so `mise install` inside a component works too.
Run `mise trust` once in each component the first time you use mise there.

## Run everything together

1. **The service.** In `components/backend/`:

   ```sh
   mise exec -- mix setup
   mise exec -- mix phx.server
   ```

   It listens on <http://localhost:4000>; <http://localhost:4000/health> returns `{"status":"ok"}`. See the
   [backend README](https://github.com/assistant-link/backend#readme).

2. **The iOS app.** In `components/apple/`, on macOS, run the app in the Simulator against the local service:

   ```sh
   make run SERVICE_URL=http://localhost:4000
   ```

   Create an Assistant, add a Link, and copy its pairing text. See the
   [apple README](https://github.com/assistant-link/apple#readme).

3. **The agent side.** In `components/cli/`, build `al` and pair with the code from the pairing text:

   ```sh
   make build
   export AL_SERVER=http://localhost:4000
   target/debug/al pair <code>
   target/debug/al wait
   ```

   While `al wait` runs, the app shows the Link as online. See the [cli README](https://github.com/assistant-link/cli#readme).

## Tests

Each component has its own quality gate, which its CI runs on every pull request: `mix precommit` in
`components/backend/`, `make precommit` in `components/cli/`, and `make lint` and `make test` in `components/apple/`.

The integration tests in [`tests/integration/`](../tests/integration/) run the components together:

```sh
mise run test:integration
```

## Where to go next

- [High-level product spec](product/high-level-spec.md) and [product Q&A](product/qa.md)
- [Engineering principles](engineering/principles.md)
- [How to make changes](engineering/how-to-make-changes.md)
- [Assistant Link Protocol v1](https://github.com/assistant-link/backend/blob/main/docs/alp/v1.md), for building your
  own agent integration
- [Self-hosting the service](https://github.com/assistant-link/backend/blob/main/deploy/SELF_HOSTING.md)
- [Contributing](../CONTRIBUTING.md)
