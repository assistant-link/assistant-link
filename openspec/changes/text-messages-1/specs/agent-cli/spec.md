## MODIFIED Requirements

### Requirement: Output format
`al` SHALL print machine-readable JSON by default and human-readable text when run with `--human`. `al pair`, `al status`, and `al send` SHALL print one JSON object on standard output, including on failure. Usage errors MAY be printed as text. The exit code SHALL signal the outcome in either format.

#### Scenario: Default output
- **WHEN** the agent runs `al status`
- **THEN** standard output is exactly one JSON object

#### Scenario: Human output
- **WHEN** the agent runs `al status --human`
- **THEN** `al` prints the same information as text
- **AND** exits with the same exit code as without `--human`

### Requirement: Link key input
`al status`, `al wait`, and `al send` SHALL read the Link key from the file given by `--key-file`, else from the `AL_LINK_KEY` environment variable, ignoring surrounding whitespace. `al` SHALL NOT accept the key as a command-line value and SHALL NOT keep Link keys or other state on the host.

#### Scenario: Two Links on one host user
- **WHEN** the same host user runs two `al wait` processes, each with a different Assistant Link's key
- **THEN** both Assistant Links show online, and stopping one leaves the other online

#### Scenario: No key
- **WHEN** neither `--key-file` nor `AL_LINK_KEY` is given, or the key file is missing, unreadable, or empty
- **THEN** `al status` reports `check` `no_key` with a message naming `AL_LINK_KEY`, `--key-file`, and `al pair <code>`, and exits with the "no key" exit code

### Requirement: Status
`al status` SHALL check once whether the service accepts the supplied Link key by calling only `GET /alp/v1/link`; it SHALL NOT open the agent connection or make the Link online. It SHALL print `{"server", "link_id"?, "assistant_name"?, "unread_count"?, "check", "error"?}`: the service URL it uses, the Link id, Assistant name, and unread count the service reports (only when `accepted`), and the result of the check as `check`: `accepted`, `rejected`, `unreachable`, `no_key`, or `unexpected` (for example, a service that does not speak ALP, or an unexpected HTTP status). Any result other than `accepted` SHALL include `error` with a `code` and `message`. It SHALL exit 0 only if the key is accepted.

#### Scenario: Not an Assistant Link service
- **WHEN** the service URL answers `GET /alp/v1/link` with an unexpected HTTP status, such as `404`
- **THEN** `al status` reports `check` `unexpected` and exits with the "unexpected error" exit code

#### Scenario: Paired and reachable
- **WHEN** the supplied Link key is valid and the service is reachable
- **THEN** `al status` reports the Assistant name, Link id, `unread_count`, and `check` `accepted`, and exits 0

#### Scenario: Key not accepted
- **WHEN** the service does not accept the supplied Link key (for example, the account was deleted, or the key was issued by another service)
- **THEN** `al status` reports `check` `rejected` with a message naming the service URL it used, and exits with the "rejected" exit code

#### Scenario: Status leaves the Link alone
- **WHEN** the agent runs `al status` for an offline Link with undelivered messages
- **THEN** the Link stays offline, its cursor does not move, and no event is delivered

### Requirement: Wait (hold the connection)
`al wait` SHALL open the agent connection and keep it open until interrupted, so the Assistant Link is online while it runs. It SHALL reconnect automatically after a lost connection, waiting longer between repeated failures (up to 30 seconds). It SHALL read the Link key once at startup and exit with the "no key" exit code when none is supplied. It SHALL stop and exit with the "rejected" exit code if the service rejects the Link key or closes the connection with reason `account_deleted`. On SIGINT or SIGTERM it SHALL close the connection cleanly and exit 0. Standard output SHALL be reserved for incoming events, written as defined in "Incoming events"; status messages SHALL go to standard error, one JSON object per line by default.

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
`al` SHALL use these exit codes: `0` success, `1` unexpected error, `2` usage error, `3` no Link key supplied, `4` rejected by the service (invalid code, Link key, or message), `5` service unreachable (including `5xx` responses).

#### Scenario: Service down
- **WHEN** the service cannot be reached during `al status`
- **THEN** `al` reports `check` `unreachable` with a message naming the service URL and exits 5

### Requirement: Agent install instructions
The service SHALL serve agent-facing install instructions (`install.md`) at the URL included in the pairing text. They SHALL cover only installing `al` for the agent's platform, pairing with the code, keeping the Link key in the host's secret storage (such as the macOS Keychain, the Linux Secret Service, or a file readable only by the agent's user) and supplying it to `al` from a small wrapper, on all platforms, and verifying with `al status`, and SHALL end with "Run `al help` and follow it". Usage, such as staying online with `al wait` and replying with `al send`, SHALL NOT be in them: it lives in the `al` help. Every command in them SHALL work as written.

#### Scenario: Agent follows install.md
- **WHEN** an agent is given the pairing text and follows the linked `install.md` on a supported host
- **THEN** `al status` exits 0 and the instructions end by telling the agent to run `al help`

#### Scenario: Two assistants on one host
- **WHEN** two agents running as the same host user each follow `install.md` with their own pairing text
- **THEN** each stores its own Link key and wrapper, and `al status` exits 0 for both

## ADDED Requirements

### Requirement: Incoming events
`al wait` SHALL write each incoming event (the params of `event.deliver`) to standard output as one compact JSON line, in both JSON and `--human` modes, in the order received. Every event SHALL have `id`, `type`, `created_at`, and `deleted`, plus the content under a key named after the type. `al` SHALL keep no position: missed events arrive as ordinary events after it connects.

#### Scenario: Message arrives
- **WHEN** `al wait` is running and the user sends "Hi"
- **THEN** standard output gains the single line `{"id": "...", "type": "text_message", "created_at": "...", "deleted": false, "text_message": {"text": "Hi"}}`
- **AND** the user's message becomes "Delivered" only after that line was written

#### Scenario: Deleted message arrives
- **WHEN** the content of a message was deleted and its event is delivered to `al wait`
- **THEN** standard output gains a line with `"deleted": true` and no `text_message` key

#### Scenario: Later kinds
- **WHEN** a later kind of event arrives
- **THEN** it has its own `type` and content key, and existing kinds only gain optional fields

#### Scenario: Messages sent while not running
- **WHEN** the user sent "a" and "b" while `al wait` was not running, and it then starts
- **THEN** standard output gains the line for "a" and then the line for "b"

#### Scenario: Multi-line text
- **WHEN** the user sends a message with a line break
- **THEN** the event is still one line, with the line break escaped in `text`

#### Scenario: Human mode keeps events as JSON
- **WHEN** `al wait --human` receives a message
- **THEN** standard output gets the same JSON line and only status messages on standard error are text

### Requirement: Acknowledge an event after writing it
`al wait` SHALL have a single writer for standard output that never abandons a write, so it never prints a broken or interleaved line. It SHALL answer `event.deliver` with the result `{"event_id": "<the event id>"}` (also for a repeat it suppresses) only after the line has been written and flushed: write, flush, then acknowledge. While a write is pending, it SHALL answer any further `event.deliver` with error `-32001` (`data.reason` `not_received`) and report it on standard error.

#### Scenario: Nothing reads standard output
- **WHEN** the process reading `al wait`'s standard output has stopped reading (the pipe is full), and a message arrives
- **THEN** the write stays pending and the message is not "Delivered" by this Assistant Link
- **AND** any further `event.deliver` is answered with error `-32001` `not_received`, nothing is interleaved on standard output, and the Assistant Link stays online

#### Scenario: Written once the reader is back
- **WHEN** the reader resumes reading
- **THEN** the pending line is written whole and acknowledged, and later events follow in order

### Requirement: Shutdown with a pending write
On SIGINT or SIGTERM `al wait` SHALL exit as specified without waiting for a pending write. The event was not acknowledged, so the service redelivers it later.

#### Scenario: Shutdown with a pending write
- **WHEN** a write to standard output is pending (the reader stopped reading) and `al wait` receives SIGINT or SIGTERM
- **THEN** it exits as specified without waiting for the write, and the event is not acknowledged, so the service sends it again later

### Requirement: Exit when standard output is closed
If the write to standard output fails with a broken pipe, as opposed to a full pipe that keeps the write pending, `al wait` SHALL report it on standard error, close the connection, and exit with code 1, so the Assistant Link goes offline instead of rejecting every event while online.

#### Scenario: Standard output is closed
- **WHEN** the process reading `al wait`'s standard output has closed it, and a write fails with a broken pipe
- **THEN** `al wait` reports it on standard error, closes the connection, and exits with code 1
- **AND** the Assistant Link goes offline

### Requirement: Drop a repeat of the last event
`al wait` SHALL remember the id of the last line it wrote and, when an event with that id arrives again, acknowledge it, with its `event_id`, without writing. Since the service keeps one event in flight per Assistant Link, a repeat can only be the last event written; only a restart of `al wait`, or two `al wait` processes on one Link, can show the last event once more.

#### Scenario: Same id arrives again
- **WHEN** `al wait` wrote the line for a message, its connection dropped before the acknowledgement, and it reconnects
- **THEN** the service sends the same event again, and `al wait` acknowledges it with the `event_id` without writing the line a second time

#### Scenario: Restart repeats the last event
- **WHEN** `al wait` wrote the last line, was restarted before the acknowledgement reached the service, and starts again
- **THEN** the same line, with the same `id`, may appear once more

### Requirement: Send a message
`al send <text>` SHALL send a text message to the user as the Assistant of the Assistant Link with `POST /alp/v1/messages`, without opening an agent connection or changing the Assistant Link's presence. With `-` as the text it SHALL read standard input as UTF-8, dropping one trailing line feed. It SHALL print `{"message_id", "created_at"}` and exit 0, or `{"error": {"code", "message"}}` and the matching exit code on failure. Without a text it SHALL report a usage error.

#### Scenario: Send as an argument
- **WHEN** the agent runs `al send "Your reminder is set."`
- **THEN** `al` prints the new `message_id` and `created_at` and exits 0
- **AND** the message appears in the Assistant's Timeline in the app

#### Scenario: Send from standard input
- **WHEN** the agent runs `printf 'line 1\nline 2\n' | al send -`
- **THEN** the message text is `line 1` and `line 2` on two lines, without a trailing line feed

#### Scenario: No presence change
- **WHEN** the agent runs `al send "Hi"` while its Assistant Link is offline
- **THEN** the message is sent and the Assistant Link stays offline

#### Scenario: Text too long
- **WHEN** the agent sends a text the service rejects as too long
- **THEN** `al` prints an error with code `text_too_long` and exits with the "rejected" exit code

#### Scenario: Service unreachable
- **WHEN** the agent runs `al send "Hi"` and the service cannot be reached
- **THEN** `al` prints an error and exits with the "service unreachable" exit code

#### Scenario: No text
- **WHEN** the agent runs `al send` without a text
- **THEN** `al` reports a usage error and exits with the "usage error" exit code

#### Scenario: No key
- **WHEN** the agent runs `al send "Hi"` with neither `--key-file` nor `AL_LINK_KEY`
- **THEN** `al` prints an error naming `AL_LINK_KEY` and `--key-file` and exits with the "no key" exit code (3)

### Requirement: Send makes one attempt
`al send` SHALL generate a fresh UUIDv7 `idempotency_key` per invocation and send it, make one attempt, and not retry.

#### Scenario: Key per invocation
- **WHEN** the agent runs `al send "Hi"` twice
- **THEN** each request carries a different UUIDv7 `idempotency_key`

#### Scenario: Retry after unreachable
- **WHEN** `al send` exits with the "service unreachable" exit code after the service stored the message, and the agent runs it again
- **THEN** the message is stored twice, because the second invocation has a new `idempotency_key`, unless the agent calls the API directly and reuses one

### Requirement: Usage help
`al help` SHALL be short and general only: what `al` is, the list of commands one line each, the overall flow (stay online with `al wait`, reply with `al send`), a short Link key section, and "run `al <command> --help` for details". It SHALL NOT repeat subcommand help, so it can grow without becoming one giant text. Help ships in the binary, so it is bound to the installed version.

#### Scenario: General only
- **WHEN** the agent runs `al help`
- **THEN** it lists each command in one line and points to `al <command> --help` for details, without the event format or the text rules

### Requirement: Subcommand help
`al wait --help` SHALL describe receiving: one JSON line per event, the nested format, the stable `id` and that the last event may repeat once after a restart, that missed events arrive first, and deleted events. `al send --help` SHALL describe replying: the text rules and the `idempotency_key`. `al status --help` SHALL describe the check: that it calls `GET /alp/v1/link` without connecting, the output fields, `unread_count`, and the `check` values.

#### Scenario: Receiving details
- **WHEN** the agent runs `al wait --help`
- **THEN** it describes the JSON line per event, the nested format, the stable `id`, that the last event may repeat once after a restart, that missed events arrive first, and deleted events

#### Scenario: Replying details
- **WHEN** the agent runs `al send --help`
- **THEN** it describes the text rules and the `idempotency_key`

#### Scenario: Status details
- **WHEN** the agent runs `al status --help`
- **THEN** it says that the command only asks the service (it does not connect or make the Link online) and describes the output fields, `unread_count`, and the `check` values

### Requirement: Link key help
The Link key section of `al help` SHALL show only the example for the current operating system (macOS: the Keychain only; Linux: the Secret Service plus a file readable only by the user as a fallback; other systems: the file) and SHALL always say "If your environment has a safer way to guard credentials, use it instead."

#### Scenario: Help on macOS
- **WHEN** the agent runs `al help` on macOS
- **THEN** the Link key section shows the Keychain and not the Linux options
- **AND** it ends with "If your environment has a safer way to guard credentials, use it instead."

#### Scenario: Help on Linux
- **WHEN** the agent runs `al help` on Linux
- **THEN** the Link key section shows the Secret Service and the user-only-readable file fallback, and not the Keychain
