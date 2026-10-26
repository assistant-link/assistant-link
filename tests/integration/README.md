# Integration tests

Tests that run the components together, from the repositories cloned by `scripts/clone`. Each component's own tests
stay in its repository; these cover what only shows up when the pieces talk to each other.

## smoke.sh

Starts the backend from `components/backend/` with its production configuration against a local Postgres, checks
`/health`, builds `al` from `components/cli/`, and runs it against that backend as far as it goes without the app:

1. creates an account, an Assistant, a Link, and a pairing code through the client API, as the app would;
2. `al pair` with that code into a key file, then `al status` with that key file;
3. `al wait` with the key in `AL_LINK_KEY`, checking that the Link goes online, and offline again once `al wait` stops;
4. checks that `/install.md` points agents at the `cli` repository.

Then `smoke.sh` sources [`messages.sh`](messages.sh): text messages between the app API and `al` on the same backend,
one `test_*` function per scenario (delivery, catch-up, two Links, unread stdout, `al send`, `al status`, account
deletion and purge), each with its own account.

Not covered, because the backend fixes the delivery retry at 30 s: `al wait` answering `-32001` `not_received`, and the
retry, backoff, and timeout themselves.

Run it from the repository root:

```sh
mise run test:integration
```

It needs the components cloned (`mise run clone`), the tools from `mise install`, `curl`, `jq`, `psql`, and Postgres at
`DATABASE_URL` (default `ecto://postgres:postgres@localhost:5432/assistant_link_smoke`; the database is created if
missing). The backend listens on port 4100 (`SMOKE_PORT`), so it does not clash with a dev server on 4000.

CI runs it on every pull request and on every push to `main`, against the component branches set in the workflow
([`.github/workflows/integration.yml`](../../.github/workflows/integration.yml)).

## Adding a test

Add a `test_*` function to `messages.sh` and call it at the end of `smoke.sh`, or add a script here and a step that runs
it in `integration.yml`. Keep each one runnable locally with the same command CI uses. Start a `messages.sh` test with
`new_account`, so it depends on no other test's data, and stop every `al wait` it starts.

`scripts/clone` takes `ASSISTANT_LINK_BACKEND_REF`, `ASSISTANT_LINK_CLI_REF`, and `ASSISTANT_LINK_APPLE_REF` (default
`main`) to test unmerged branches.
