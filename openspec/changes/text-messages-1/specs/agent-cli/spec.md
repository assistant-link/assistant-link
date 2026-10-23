## MODIFIED Requirements

### Requirement: Output format
`al` SHALL print machine-readable JSON by default and text with `--human`.
`al pair`, `al status`, and `al send` SHALL print one JSON object on standard output, including on failure. Usage errors MAY be text.
The exit code SHALL signal the outcome in either format.

#### Scenario: Default output
- **WHEN** the agent runs `al status`
- **THEN** standard output is exactly one JSON object

#### Scenario: Human output
- **WHEN** the agent runs `al status --human`
- **THEN** `al` prints the same information as text, with the same exit code

### Requirement: Link key input
`al status`, `al wait`, and `al send` SHALL read the Link key from the file given by `--key-file`, else from `AL_LINK_KEY`, ignoring surrounding whitespace.
`al` SHALL NOT accept the key as a command-line value and SHALL NOT keep Link keys or other state on the host.

#### Scenario: Two Links on one host user
- **WHEN** the same host user runs two `al wait` processes with different Links' keys
- **THEN** both Links show online, and stopping one leaves the other online

#### Scenario: No key
- **WHEN** neither `--key-file` nor `AL_LINK_KEY` is given, or the key file is missing, unreadable, or empty
- **THEN** `al status` reports `check` `no_key` naming `AL_LINK_KEY`, `--key-file`, and `al pair <code>`, and exits with the "no key" code

### Requirement: Status
`al status` SHALL check once whether the service accepts the Link key, calling only `GET /alp/v1/link`.
It SHALL NOT open the agent connection or make the Link online.
It SHALL print `{"server", "link_id"?, "assistant_name"?, "unread_count"?, "check", "error"?}`.
The Link fields appear only when `accepted`.
`check` is `accepted`, `rejected`, `unreachable`, `no_key`, or `unexpected` (not an ALP service, or an unexpected HTTP status).
Any result other than `accepted` SHALL include `error` with `code` and `message`.
It SHALL exit 0 only if the key is accepted.

#### Scenario: Paired and reachable
- **WHEN** the key is valid and the service reachable
- **THEN** `al status` reports the Assistant name, Link id, `unread_count`, and `check` `accepted`, and exits 0

#### Scenario: Not an Assistant Link service
- **WHEN** `GET /alp/v1/link` answers with an unexpected status such as `404`
- **THEN** `al status` reports `check` `unexpected` and exits with the "unexpected error" code

#### Scenario: Key not accepted
- **WHEN** the service does not accept the key (for example the account was deleted)
- **THEN** `al status` reports `check` `rejected` naming the service URL, and exits with the "rejected" code

### Requirement: Wait (hold the connection)
`al wait` SHALL open the agent connection and keep it open until interrupted, so the Link is online while it runs.
It SHALL reconnect after a lost connection, waiting longer between repeated failures (up to 30 seconds).
It SHALL read the Link key once at startup and exit with the "no key" code when none is supplied.
It SHALL stop with the "rejected" code if the service rejects the key or closes with reason `account_deleted`.
On SIGINT or SIGTERM it SHALL close cleanly and exit 0.
Standard output is reserved for incoming events (see "Incoming events").
Status messages go to standard error, one JSON object per line by default.

#### Scenario: Link online while waiting
- **WHEN** the agent runs `al wait`
- **THEN** the Link shows online in the app while it runs

#### Scenario: Interrupted
- **WHEN** `al wait` receives SIGINT
- **THEN** it closes cleanly, the Link goes offline, and `al` exits 0

#### Scenario: Network drop
- **WHEN** the connection drops
- **THEN** `al wait` reconnects when the network returns

#### Scenario: Account deleted
- **WHEN** the user logs out while `al wait` runs
- **THEN** `al wait` reports it and exits with the "rejected" code

### Requirement: Exit codes
`al` SHALL use these exit codes: `0` success, `1` unexpected error, `2` usage error, `3` no Link key supplied,
`4` rejected by the service (invalid code, Link key, or message), `5` service unreachable (including `5xx`).

#### Scenario: Service down
- **WHEN** the service cannot be reached during `al status`
- **THEN** `al` reports `check` `unreachable` naming the service URL and exits 5

### Requirement: Agent install instructions
The service SHALL serve agent-facing install instructions (`install.md`) at the URL in the pairing text.
They SHALL only install `al`, pair with the code, store the Link key in the host's secret storage with a small wrapper, and verify with `al status`.
They SHALL end with "Run `al help` and follow it".
Every command in them SHALL work as written.

#### Scenario: Agent follows install.md
- **WHEN** an agent follows `install.md` on a supported host
- **THEN** `al status` exits 0 and the instructions end by telling it to run `al help`

#### Scenario: Two assistants on one host
- **WHEN** two agents of the same host user each follow `install.md` with their own pairing text
- **THEN** each stores its own key and wrapper, and `al status` exits 0 for both

## ADDED Requirements

### Requirement: Incoming events
`al wait` SHALL write each incoming event (the params of `event.deliver`) to standard output as one compact JSON line, in order, in both JSON and `--human` modes.
`al` SHALL keep no position: missed events arrive first after it connects.

#### Scenario: Message arrives
- **WHEN** `al wait` is running and the user sends "Hi"
- **THEN** standard output gains the line `{"id": "...", "type": "text_message", "created_at": "...", "deleted": false, "text_message": {"text": "Hi"}}`

### Requirement: Acknowledge an event after writing it
`al wait` SHALL have a single writer for standard output that never abandons a write.
It SHALL answer `event.deliver` with `{"event_id": "<the event id>"}` only after the line was written and flushed.
While a write is pending it SHALL answer further `event.deliver` with `-32001` (`data.reason` `not_received`) and report it on standard error.
It SHALL remember the last id written and acknowledge a repeat of it without writing.

#### Scenario: Nothing reads standard output
- **WHEN** the reader stopped reading and a message arrives
- **THEN** the write stays pending and the message is not acknowledged
- **AND** further events get `-32001` `not_received`, and the Link stays online

#### Scenario: Same id arrives again
- **WHEN** `al wait` wrote a line, its connection dropped before the acknowledgement, and it reconnects
- **THEN** it acknowledges the repeated event without writing a second line

### Requirement: Shutdown with a pending write
On SIGINT or SIGTERM `al wait` SHALL exit without waiting for a pending write. The event stays unacknowledged.
If a write fails with a broken pipe, it SHALL report it on standard error, close the connection, and exit 1.

#### Scenario: Shutdown with a pending write
- **WHEN** a write is pending and `al wait` receives SIGINT
- **THEN** it exits without waiting, and the event is not acknowledged

#### Scenario: Standard output is closed
- **WHEN** the reader closed standard output and a write fails
- **THEN** `al wait` reports it, exits 1, and the Link goes offline

### Requirement: Send a message
`al send <text>` SHALL send a message with `POST /alp/v1/messages`, without opening an agent connection.
With `-` as the text it SHALL read standard input as UTF-8, dropping one trailing line feed.
It SHALL use a fresh UUIDv7 `idempotency_key` per run, make one attempt, and not retry.
It SHALL print `{"message_id", "created_at"}` and exit 0, or `{"error": {"code", "message"}}` and the matching exit code.
Without a text it SHALL report a usage error.

#### Scenario: Send as an argument
- **WHEN** the agent runs `al send "Your reminder is set."` while its Link is offline
- **THEN** `al` prints `message_id` and `created_at`, exits 0, and the Link stays offline

#### Scenario: Failures
- **WHEN** the service rejects the text as `text_too_long`, cannot be reached, no text is given, or no key is given
- **THEN** `al` exits 4, 5, 2, or 3 respectively

### Requirement: Usage help
`al help` SHALL be short and general: each command in one line, the flow (`al wait` to stay online, `al send` to reply),
a short Link key section, and "run `al <command> --help` for details".
`al wait --help` SHALL describe the event line and missed events first.
`al send --help` SHALL describe the text rules and `idempotency_key`.
`al status --help` SHALL describe the output fields and `check` values.

#### Scenario: General only
- **WHEN** the agent runs `al help`
- **THEN** it lists each command in one line and points to `al <command> --help`

### Requirement: Link key help
The Link key section of `al help` SHALL show only the current OS option (macOS: the Keychain; Linux: the Secret Service plus a user-only file; others: the file).
It SHALL always say "If your environment has a safer way to guard credentials, use it instead."

#### Scenario: Help on macOS
- **WHEN** the agent runs `al help` on macOS
- **THEN** the section shows the Keychain only and ends with "If your environment has a safer way to guard credentials, use it instead."
