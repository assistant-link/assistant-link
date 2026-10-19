# agent-cli Specification

## Purpose

Defines the `al` command-line tool that agents (and people) run on the agent host to pair with and connect to Assistant Link, as a single self-contained binary usable by any agent that can run shell commands.

## Requirements

### Requirement: Self-contained binary
`al` SHALL be distributed as a single executable for macOS (Apple Silicon and Intel) and Linux (x86_64 and arm64) that runs without installing a language runtime or other dependencies.

#### Scenario: Runs on a clean host
- **WHEN** the `al` binary is copied to a supported host with no extra software installed
- **THEN** `al --version` prints its version and exits 0

### Requirement: Pair with a code
`al pair <code>` SHALL exchange the pairing code for the Link's key (its Link token) using ALP. On success it SHALL print `{"server", "link_id", "assistant_name", "link_key"}`; on failure it SHALL print `{"error": {"code", "message"}}`. With `--key-file <path>` it SHALL instead write the key to a new file readable and writable only by the current user and leave `link_key` out of the output; it SHALL refuse a path that already exists before sending the code. `al pair` SHALL NOT write anything else on the host.

#### Scenario: Successful pairing
- **WHEN** the agent runs `al pair K7QM-2XPA`
- **THEN** `al` prints the service URL, Link id, Assistant name, and Link key and exits 0
- **AND** writes no file

#### Scenario: Pairing into a key file
- **WHEN** the agent runs `al pair K7QM-2XPA --key-file ~/.hermes/al-key`
- **THEN** `al` writes the Link key to `~/.hermes/al-key`, readable and writable only by the current user
- **AND** prints the service URL, Link id, and Assistant name without the Link key, and exits 0

#### Scenario: Key file already exists
- **WHEN** the agent runs `al pair K7QM-2XPA --key-file <path>` and `<path>` already exists
- **THEN** `al` does not send the code, reports `key_file_exists`, and exits with the "usage error" exit code

#### Scenario: Bad code
- **WHEN** the agent runs `al pair` with an expired or invalid code
- **THEN** `al` prints the service's error code and message, writes no key file, and exits with the "rejected" exit code

### Requirement: Service URL
Every command SHALL use the service URL given by `--server`, else by the `AL_SERVER` environment variable, else the production service URL. `al` SHALL NOT record which service issued a Link key; the caller uses the service named in the pairing text.

#### Scenario: Non-production service
- **WHEN** the agent runs `al status` with `AL_SERVER=https://example.test`
- **THEN** `al` connects to `https://example.test`

#### Scenario: Production by default
- **WHEN** the agent runs `al status` without `--server` or `AL_SERVER`
- **THEN** `al` connects to the production service

### Requirement: Output format
`al` SHALL print machine-readable JSON by default and human-readable text when run with `--human`. `al pair` and `al status` SHALL print one JSON object on standard output, including on failure. Usage errors MAY be printed as text. The exit code SHALL signal the outcome in either format.

#### Scenario: Default output
- **WHEN** the agent runs `al status`
- **THEN** standard output is exactly one JSON object

#### Scenario: Human output
- **WHEN** the agent runs `al status --human`
- **THEN** `al` prints the same information as text
- **AND** exits with the same exit code as without `--human`

### Requirement: Link key input
`al status` and `al wait` SHALL read the Link key from the file given by `--key-file`, else from the `AL_LINK_KEY` environment variable, ignoring surrounding whitespace. `al` SHALL NOT accept the key as a command-line value and SHALL NOT keep Link keys or other state on the host.

#### Scenario: Two Links on one host user
- **WHEN** the same host user runs two `al wait` processes, each with a different Link's key
- **THEN** both Links show online, and stopping one leaves the other online

#### Scenario: No key
- **WHEN** neither `--key-file` nor `AL_LINK_KEY` is given, or the key file is missing, unreadable, or empty
- **THEN** `al status` reports `check` `no_key` with a message naming `AL_LINK_KEY`, `--key-file`, and `al pair <code>`, and exits with the "no key" exit code

### Requirement: Status
`al status` SHALL check once whether the service accepts a connection with the supplied Link key, then close the connection. It SHALL print `{"server", "link_id"?, "assistant_name"?, "check", "error"?}`: the service URL it uses, the Link id and Assistant name the service reports in `connection.ready`, and the result of the check as `check`: `accepted`, `rejected`, `unreachable`, `no_key`, or `unexpected` (for example, a service that does not speak ALP). Any result other than `accepted` SHALL include `error` with a `code` and `message`. It SHALL exit 0 only if the connection is accepted.

#### Scenario: Not an Assistant Link service
- **WHEN** the service URL answers the agent connection with an unexpected HTTP status, such as `404`
- **THEN** `al status` reports `check` `unexpected` and exits with the "unexpected error" exit code

#### Scenario: Paired and reachable
- **WHEN** the supplied Link key is valid and the service is reachable
- **THEN** `al status` reports the Assistant name, Link id, and `check` `accepted`, and exits 0

#### Scenario: Key not accepted
- **WHEN** the service does not accept the supplied Link key (for example, the account was deleted, or the key was issued by another service)
- **THEN** `al status` reports `check` `rejected` with a message naming the service URL it used, and exits with the "rejected" exit code

### Requirement: Wait (hold the connection)
`al wait` SHALL open the agent connection and keep it open until interrupted, so the Assistant Link is online while it runs. It SHALL reconnect automatically after a lost connection, waiting longer between repeated failures (up to 30 seconds). It SHALL read the Link key once at startup and exit with the "no key" exit code when none is supplied. It SHALL stop and exit with the "rejected" exit code if the service rejects the Link key or closes the connection with reason `account_deleted`. On SIGINT or SIGTERM it SHALL close the connection cleanly and exit 0. Standard output SHALL be reserved for incoming events (none are defined yet); status messages SHALL go to standard error, one JSON object per line by default.

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
`al` SHALL use these exit codes: `0` success, `1` unexpected error, `2` usage error, `3` no Link key supplied, `4` rejected by the service (invalid code or Link key), `5` service unreachable (including `5xx` responses).

#### Scenario: Service down
- **WHEN** the service cannot be reached during `al status`
- **THEN** `al` reports `check` `unreachable` with a message naming the service URL and exits 5

### Requirement: Agent install instructions
The service SHALL serve agent-facing install instructions (`install.md`) at the URL included in the pairing text. They SHALL tell an agent how to install `al` for its platform, pair with the code, keep the Link key in the host's secret storage (such as the macOS Keychain, the Linux Secret Service, or a file readable only by the agent's user) and supply it to `al` from a small wrapper, verify with `al status`, and keep the Link online with `al wait`. Every command in them SHALL work as written.

#### Scenario: Agent follows install.md
- **WHEN** an agent is given the pairing text and follows the linked `install.md` on a supported host
- **THEN** `al status` exits 0 and, while `al wait` runs, the Link shows online in the app

#### Scenario: Two assistants on one host
- **WHEN** two agents running as the same host user each follow `install.md` with their own pairing text
- **THEN** both Links show online while their `al wait` processes run
