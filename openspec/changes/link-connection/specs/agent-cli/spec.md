# Spec Delta

## Purpose

Defines the `al` command-line tool that agents (and people) run on the agent host to pair with and connect to Assistant Link, as a single self-contained binary usable by any agent that can run shell commands.

## ADDED Requirements

### Requirement: Self-contained binary
`al` SHALL be distributed as a single executable for macOS (Apple Silicon and Intel) and Linux (x86_64 and arm64) that runs without installing a language runtime or other dependencies.

#### Scenario: Runs on a clean host
- **WHEN** the `al` binary is copied to a supported host with no extra software installed
- **THEN** `al --version` prints its version and exits 0

### Requirement: Pair with a code
`al pair <code>` SHALL exchange the pairing code for a Link token using ALP and store the credential locally, together with the service URL that issued it. On success it SHALL print `{"server", "link_id", "assistant_name"}`; on failure it SHALL print `{"error": {"code", "message"}}`.

#### Scenario: Successful pairing
- **WHEN** the agent runs `al pair K7QM-2XPA --server https://example.test`
- **THEN** `al` stores the credential for that Link and the service URL `https://example.test`
- **AND** prints the service URL, Link id, and Assistant name and exits 0

#### Scenario: Bad code
- **WHEN** the agent runs `al pair` with an expired or invalid code
- **THEN** `al` prints the service's error code and message, leaves any stored credential unchanged, and exits with the "rejected" exit code

### Requirement: Service URL
Every command SHALL use the service URL given by `--server`, else by the `AL_SERVER` environment variable, else the production service URL. `al status` and `al wait` SHALL NOT send the stored Link token to any service other than the one that issued it: when the service URL in use differs from the stored one, they SHALL report a server mismatch naming both URLs and exit with the "server mismatch" exit code. URLs SHALL be compared ignoring trailing slashes and the case of the scheme and host.

#### Scenario: Service differs from the one that issued the credential
- **WHEN** a credential issued by `https://a.example` is stored and the agent runs `al status --server https://b.example`
- **THEN** `al` does not connect to either service
- **AND** reports `check` `server_mismatch` with both URLs and exits with the "server mismatch" exit code

#### Scenario: Background process started without AL_SERVER
- **WHEN** a credential issued by a non-production service is stored and the agent runs `al wait` without `--server` or `AL_SERVER`
- **THEN** `al wait` reports the server mismatch and exits with the "server mismatch" exit code instead of sending the token to the production service

### Requirement: Output format
`al` SHALL print machine-readable JSON by default and human-readable text when run with `--human`. `al pair` and `al status` SHALL print one JSON object on standard output, including on failure. Usage errors MAY be printed as text. The exit code SHALL signal the outcome in either format.

#### Scenario: Default output
- **WHEN** the agent runs `al status`
- **THEN** standard output is exactly one JSON object

#### Scenario: Human output
- **WHEN** the agent runs `al status --human`
- **THEN** `al` prints the same information as text
- **AND** exits with the same exit code as without `--human`

### Requirement: Local credential storage
`al` SHALL store one Link credential per host user, in `$XDG_CONFIG_HOME/assistant-link/` (defaulting to `~/.config/assistant-link/`), readable and writable only by the current user. A successful `al pair` SHALL replace any previously stored credential.

#### Scenario: Pairing again replaces the stored credential
- **WHEN** a credential for Link A is stored and the agent successfully pairs with a code for Link B
- **THEN** `al` stores Link B's credential and no longer uses Link A's
- **AND** Link A itself stays paired on the service

#### Scenario: Credential file permissions
- **WHEN** `al pair` stores a credential
- **THEN** the credential file is readable and writable only by the current user

### Requirement: Status
`al status` SHALL check once whether the service accepts a connection with the stored credential, then close the connection. It SHALL print `{"server", "paired", "link_id", "assistant_name", "check", "error"?}`: the service URL it uses, whether a credential is stored, the stored Link id and Assistant name, and the result of the check as `check`: `accepted`, `rejected`, `unreachable`, `not_paired`, `server_mismatch`, or `unexpected` (for example, an unreadable credential file or a service that does not speak ALP). Any result other than `accepted` SHALL include `error` with a `code` and `message`. It SHALL exit 0 only if the connection is accepted.

#### Scenario: Not an Assistant Link service
- **WHEN** the service URL answers the agent connection with an unexpected HTTP status, such as `404`
- **THEN** `al status` reports `check` `unexpected` with the stored Link id and Assistant name, and exits with the "unexpected error" exit code

#### Scenario: Paired and reachable
- **WHEN** the stored credential is valid and the service is reachable
- **THEN** `al status` reports the Assistant name, Link id, and `check` `accepted`, and exits 0

#### Scenario: Not paired
- **WHEN** no credential is stored
- **THEN** `al status` reports `paired` false and `check` `not_paired`, with a message suggesting `al pair <code>`, and exits with the "not paired" exit code

#### Scenario: Credential no longer accepted
- **WHEN** the service no longer accepts the stored Link token (for example, the account was deleted)
- **THEN** `al status` reports `check` `rejected` and exits with the "rejected" exit code

### Requirement: Wait (hold the connection)
`al wait` SHALL open the agent connection and keep it open until interrupted, so the Assistant Link is online while it runs. It SHALL reconnect automatically after a lost connection, waiting longer between repeated failures (up to 30 seconds). It SHALL stop and exit with the "rejected" exit code if the service rejects the credential or closes the connection with reason `account_deleted`. On SIGINT or SIGTERM it SHALL close the connection cleanly and exit 0. Standard output SHALL be reserved for incoming events (none are defined yet); status messages SHALL go to standard error, one JSON object per line by default.

#### Scenario: Link online while waiting
- **WHEN** the agent runs `al wait`
- **THEN** the Assistant Link shows online in the app while it runs

#### Scenario: Interrupted
- **WHEN** `al wait` receives SIGINT
- **THEN** it closes the connection cleanly, the Link becomes offline, and `al` exits 0

#### Scenario: Network drop
- **WHEN** the connection drops because of a network error
- **THEN** `al wait` reconnects when the network returns, without the agent re-running it

#### Scenario: Account deleted
- **WHEN** the user logs out in the app while `al wait` is running
- **THEN** `al wait` reports that the account was deleted and exits with the "rejected" exit code

### Requirement: Exit codes
`al` SHALL use these exit codes: `0` success, `1` unexpected error, `2` usage error, `3` not paired, `4` rejected by the service (invalid code or credential), `5` service unreachable (including `5xx` responses), `6` server mismatch (the stored credential was issued by a different service).

#### Scenario: Service down
- **WHEN** the service cannot be reached during `al status`
- **THEN** `al` reports `check` `unreachable` with a message naming the service URL and exits 5

### Requirement: Agent install instructions
The service SHALL serve agent-facing install instructions (`install.md`) at the URL included in the pairing text. They SHALL tell an agent how to install `al` for its platform, pair with the code, verify with `al status`, and keep the Link online with `al wait`. Every command in them SHALL work as written.

#### Scenario: Agent follows install.md
- **WHEN** an agent is given the pairing text and follows the linked `install.md` on a supported host
- **THEN** `al status` exits 0 and, while `al wait` runs, the Link shows online in the app
