## MODIFIED Requirements

### Requirement: Agent connection speaks JSON-RPC 2.0
The service SHALL accept a WebSocket connection at `GET /alp/v1/connect` authenticated by a Link token.
Every text frame in either direction SHALL contain exactly one JSON-RPC 2.0 message (request, response, or notification). Batches SHALL NOT be used.
Service-to-agent events SHALL be notifications, except an event whose delivery the service must confirm, which SHALL be a request the agent answers.
The service SHALL match responses to its requests by `id`.
A response with an unknown or expired `id` SHALL complete no request and the connection stays open,
but a `result` carrying an `event_id` SHALL still be acknowledged (see "Event acknowledgement").
Immediately after accepting a connection the service SHALL send the notification `connection.ready` with params `link_id`, `assistant_name`, and `protocol_version` (`"1"`).
While the connection is open the Assistant Link SHALL count as online.

#### Scenario: Successful connection
- **WHEN** an agent opens `/alp/v1/connect` with a valid Link token
- **THEN** the first message it receives is `{"jsonrpc": "2.0", "method": "connection.ready", "params": {"link_id": ..., "assistant_name": ..., "protocol_version": "1"}}`
- **AND** the Assistant Link is online

## ADDED Requirements

### Requirement: Event delivery request
The service SHALL deliver an event as the request `event.deliver`, whose params are the event:
`id`, `type`, `created_at` (RFC 3339 UTC), `deleted`, and the content under a key named after the type.
A deleted event has no content key.
Per Link, one `event.deliver` is in flight at a time, in event order.
An agent SHALL ignore fields and types it does not know.

#### Scenario: Message delivered
- **WHEN** the user sends "Hi" to an Assistant with an online Link
- **THEN** the agent receives `event.deliver` with params `{"id", "type": "text_message", "created_at", "deleted": false, "text_message": {"text": "Hi"}}`

### Requirement: JSON-RPC request ids
Each side SHALL number its own requests with a per-connection counter.
A request `id` SHALL only pair a response with its request, never be an event id.

#### Scenario: Counters on both sides
- **WHEN** the service sends two `event.deliver` requests and the agent sends its own request
- **THEN** each side's ids are its own counter values

### Requirement: Event acknowledgement
The agent SHALL acknowledge an event by answering `event.deliver` with the result `{"event_id": "<the event id>"}`.
The service SHALL honor it from any request or connection, however late.
Each Link's cursor advances on its own acknowledgement.
Only the first acknowledgement by any Link SHALL set `delivered_at` and send `event.updated`.
An unusable `event_id` SHALL be ignored, with no error.

#### Scenario: Acknowledged
- **WHEN** the agent answers `event.deliver` with `{"result": {"event_id": "<the event id>"}}`
- **THEN** the Link's cursor advances to that event

#### Scenario: Late or other-connection result
- **WHEN** the result arrives after 30 seconds, or on another connection
- **THEN** the cursor advances and the connection stays open

#### Scenario: Acknowledged by another Link first
- **WHEN** "Link 1" acknowledged an event and then "Link 2" does
- **THEN** "Link 2"'s cursor advances, while `delivered_at` keeps "Link 1"'s time and `event.updated` is not sent again

#### Scenario: Unusable event_id
- **WHEN** a result carries an `event_id` that is unknown, of another Assistant, a `link_created` event, or at or below the Link's starting position at pairing
- **THEN** the service advances nothing and keeps the connection open

### Requirement: Delivery errors and duplicates
An agent without `event.deliver` SHALL answer `-32601`.
An agent that cannot take an event SHALL answer `-32001` with `data.reason` `not_received`.
An error, a closed connection, or no response within 30 seconds only fails the attempt.
The service SHALL then send the event again with the same `id`.
Delivery is at least once; a reader that must not see an event twice dedupes by `id`.

#### Scenario: Agent cannot take the event
- **WHEN** an agent answers `-32001` `not_received` or `-32601`
- **THEN** the cursor does not advance, the connection stays open, and the event is sent again later

### Requirement: Retry target
The service SHALL send an unacknowledged event to the Link's next-newest connection that has not failed it.
When every open connection failed it, the service SHALL retry after 30 seconds, doubling per failed round up to 5 minutes.
A new connection SHALL reset the wait and start a round at once.

#### Scenario: Backoff
- **WHEN** every open connection failed the event twice in a row
- **THEN** the service waits 60 seconds before the next round

### Requirement: Send a message to the user
The service SHALL expose `POST /alp/v1/messages`, authenticated by a Link token,
accepting `{"text"}` and optional `idempotency_key`, and responding `201` with `{"message_id", "created_at"}`.
It SHALL work whether or not the Link is online, and SHALL NOT change presence or last active time.
Bad text gets `422` (see `messages`) and nothing is stored.

#### Scenario: Message sent
- **WHEN** an agent posts `{"text": "Your reminder is set."}` while its Link is offline
- **THEN** the response is `201` with `message_id` and `created_at`, and the Link stays offline

### Requirement: Idempotent send
`idempotency_key` SHALL be a UUIDv7, unique per account; a malformed one gets `422` `invalid_params`.
A repeated key gets `200` with the stored `{"message_id", "created_at"}`, even for a deleted message.
A repeated key with different text gets `409` `idempotency_key_conflict`.

#### Scenario: Repeated key
- **WHEN** an agent posts the same key and text twice
- **THEN** the second response is `200` with the same `message_id`, and the Timeline holds one message

#### Scenario: Reused key with other text
- **WHEN** an agent reuses a key with a different text
- **THEN** the response is `409` `idempotency_key_conflict`

### Requirement: Read the Link's status
The service SHALL expose `GET /alp/v1/link`, with the authentication and errors of `POST /alp/v1/messages`.
It SHALL respond `200` with `{"link_id", "assistant_name", "unread_count"}`, the number of deliverable events after the Link's cursor.
It SHALL only count: the cursor, presence, and last active time do not change.

#### Scenario: Count
- **WHEN** three user messages and a `link_created` event lie after the cursor of an offline Link
- **THEN** `unread_count` is 3, nothing changes, and the Link stays offline

#### Scenario: Bad token
- **WHEN** the token is missing, unknown, or of a deleted account
- **THEN** the response is `401` `unauthorized`
