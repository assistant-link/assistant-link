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

## ADDED Requirements

### Requirement: Incoming events
`al wait` SHALL write each incoming event (the params of `event.deliver`) to standard output as one compact JSON line, in both JSON and `--human` modes, in the order received. Every event SHALL have a `type`; later kinds SHALL use new `type` values and existing kinds SHALL only gain optional fields. A message from the user SHALL be `{"type": "message", "id", "text", "sent_at"}`. `al` SHALL keep no position: missed events arrive as ordinary events after it connects.

#### Scenario: Message arrives
- **WHEN** `al wait` is running and the user sends "Hi"
- **THEN** standard output gains the single line `{"type": "message", "id": "...", "text": "Hi", "sent_at": "..."}`
- **AND** the user's message becomes "Delivered" only after that line was written

#### Scenario: Messages sent while not running
- **WHEN** the user sent "a" and "b" while `al wait` was not running, and it then starts
- **THEN** standard output gains the line for "a" and then the line for "b"

#### Scenario: Duplicate after a lost acknowledgement
- **WHEN** `al wait` wrote the line for a message, its connection dropped before the acknowledgement, and it reconnects
- **THEN** the same line, with the same `id`, may appear again

#### Scenario: Multi-line text
- **WHEN** the user sends a message with a line break
- **THEN** the event is still one line, with the line break escaped in `text`

#### Scenario: Human mode keeps events as JSON
- **WHEN** `al wait --human` receives a message
- **THEN** standard output gets the same JSON line and only status messages on standard error are text

### Requirement: Acknowledge an event after writing it
`al wait` SHALL answer the service's `event.deliver` request with an empty result only after the event line has been written and flushed: write, flush, then acknowledge. The write SHALL run off the connection loop with a 5 second timeout. If it fails or times out, `al wait` SHALL answer with error `-32001` (`data.reason` `not_received`), report it on standard error, and keep running.

#### Scenario: Nothing reads standard output
- **WHEN** the process reading `al wait`'s standard output has closed it or stopped reading, and a message arrives
- **THEN** `al wait` answers `event.deliver` with error `-32001` `not_received` within about 5 seconds, so the message is not "Delivered" by this Assistant Link
- **AND** it reports the failure on standard error, keeps running, and the Assistant Link stays online

#### Scenario: Redelivered once the reader is back
- **WHEN** a message was answered with `not_received` and the reader later resumes reading
- **THEN** the service sends the message again, `al wait` writes its line, and acknowledges it

### Requirement: Send a message
`al send <text>` SHALL send a text message to the user as the Assistant of the Assistant Link with `POST /alp/v1/messages`, without opening an agent connection or changing the Assistant Link's presence. With `-` as the text it SHALL read standard input as UTF-8, dropping one trailing line feed. It SHALL print `{"message_id", "sent_at"}` and exit 0, or `{"error": {"code", "message"}}` and the matching exit code on failure. Without a text it SHALL report a usage error.

#### Scenario: Send as an argument
- **WHEN** the agent runs `al send "Your reminder is set."`
- **THEN** `al` prints the new `message_id` and `sent_at` and exits 0
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
`al send` SHALL make one attempt, send no `client_id`, and not retry.

#### Scenario: Retry after unreachable
- **WHEN** `al send` exits with the "service unreachable" exit code after the service stored the message, and the agent runs it again
- **THEN** the message is stored twice, unless the agent calls the API directly with a `client_id`
