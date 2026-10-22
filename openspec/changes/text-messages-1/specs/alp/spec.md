## MODIFIED Requirements

### Requirement: Agent connection speaks JSON-RPC 2.0
The service SHALL accept a WebSocket connection at `GET /alp/v1/connect` authenticated by a Link token. Every text frame in either direction SHALL contain exactly one JSON-RPC 2.0 message (request, response, or notification); batches SHALL NOT be used. Service-to-agent events SHALL be JSON-RPC notifications, except an event whose delivery the service must confirm, which SHALL be a JSON-RPC request the agent answers. The service SHALL accept the agent's responses and match them to its requests by `id`; a response with an unknown or expired `id` SHALL be ignored and the connection stays open. Immediately after accepting a connection the service SHALL send the notification `connection.ready` with params `link_id`, `assistant_name`, and `protocol_version` (`"1"`). While the connection is open the Assistant Link SHALL count as online.

#### Scenario: Successful connection
- **WHEN** an agent opens `/alp/v1/connect` with a valid Link token
- **THEN** the first message it receives is `{"jsonrpc": "2.0", "method": "connection.ready", "params": {"link_id": ..., "assistant_name": ..., "protocol_version": "1"}}`
- **AND** the Assistant Link is online

## ADDED Requirements

### Requirement: Event delivery request
The service SHALL deliver an event to the agent with the request `event.deliver`, whose params are the event: `id`, `type`, `created_at` (RFC 3339 UTC), and `deleted` (boolean), always present, plus the content under a key named after the type (`text_message`: `{"text"}`). A deleted event has `"deleted": true` and no content key. Only the user's text messages are delivered in this revision. The JSON-RPC request `id` SHALL be the event's `id`.

#### Scenario: Message delivered
- **WHEN** the user sends "Hi" to an Assistant that has an online Assistant Link
- **THEN** the agent receives `{"jsonrpc": "2.0", "id": ..., "method": "event.deliver", "params": {"id": ..., "type": "text_message", "created_at": ..., "deleted": false, "text_message": {"text": "Hi"}}}`

#### Scenario: Deleted message delivered
- **WHEN** the content of a message was deleted and its event is next for an online Assistant Link
- **THEN** the agent receives `event.deliver` with params `{"id": ..., "type": "text_message", "created_at": ..., "deleted": true}` and no `text_message` key

### Requirement: Event acknowledgement
A result object, which MAY be empty, SHALL acknowledge the event: the Assistant Link's cursor advances and, for the user's message, `delivered_at` is set if it was still null. An error response SHALL mean the agent did not take it, but only when it comes from the connection the event was last sent to; an error from any other connection SHALL be ignored.

#### Scenario: Acknowledged
- **WHEN** the agent responds to `event.deliver` with `{"jsonrpc": "2.0", "id": ..., "result": {}}`
- **THEN** the Assistant Link's cursor advances to that event

### Requirement: Late acknowledgement
The service SHALL accept a response for the event currently in flight as its acknowledgement even if it arrives after the 30 seconds, and SHALL ignore a response for any other id.

#### Scenario: Late response
- **WHEN** the agent responds to the event in flight after 30 seconds, before the service sent it again
- **THEN** the cursor advances and the retry is cancelled

#### Scenario: Late result from another connection
- **WHEN** the service sent the event to a second connection after the first failed, and the first then responds with a `result`
- **THEN** the cursor advances and the retry is cancelled

#### Scenario: Late error from another connection
- **WHEN** the service sent the event to a second connection and the first then responds with an error
- **THEN** the service ignores it and the event stays in flight on the second connection

#### Scenario: Response for another id
- **WHEN** the agent responds with an id that is not the event in flight
- **THEN** the service ignores it and the connection stays open

### Requirement: Event order, cursor, and catch-up
For each Assistant Link the service SHALL send one `event.deliver` request at a time, in event order, and SHALL send the next only after the agent acknowledged the previous one. Acknowledgement SHALL advance the cursor the service keeps for that Assistant Link; the agent SHALL NOT send or keep a position. After `connection.ready`, the service SHALL send the events after the cursor that are within the delivery retention.

#### Scenario: One at a time
- **WHEN** three events are waiting for an Assistant Link
- **THEN** the second request is sent only after the agent acknowledged the first

#### Scenario: Catch-up on connect
- **WHEN** an agent connects after missing two events
- **THEN** after `connection.ready` it receives them as two `event.deliver` requests, oldest first

### Requirement: Event types
Later event types SHALL be added with new `type` values and SHALL use the `event.deliver` request. An agent SHALL ignore the fields and types it does not know.

#### Scenario: Unknown event type
- **WHEN** a v1 agent receives `event.deliver` with a `type` added in a later v1 revision
- **THEN** it ignores the event's unknown parts and keeps the connection, and it acknowledges the event if it took it

### Requirement: Delivery errors and duplicates
An agent that does not implement `event.deliver` SHALL respond with `-32601`. An agent that cannot take an event SHALL respond to `event.deliver` with error `-32001` and `data.reason` `not_received`. An event whose request got an error, a closed connection, or no response within 30 seconds stays unacknowledged, and the service SHALL send it again with the same `id`. Delivery is at least once, so a reader that must not see an event twice SHALL dedupe by `id`.

#### Scenario: Agent cannot take the event
- **WHEN** an agent responds to `event.deliver` with error `-32001` and `data.reason` `not_received`
- **THEN** the cursor does not advance, the connection stays open, and the service sends the event again later

#### Scenario: Lost acknowledgement
- **WHEN** an agent wrote an event but its connection dropped before it responded, and it reconnects
- **THEN** the service sends the same event again with the same `id`

#### Scenario: Agent without event support
- **WHEN** an agent that does not implement `event.deliver` responds with `-32601`
- **THEN** the connection stays open and the cursor does not advance, and the Assistant Link receives the events once it runs a version that supports them, if they are within the delivery retention

### Requirement: Retry target
The service SHALL send an unacknowledged event to the Assistant Link's next-newest connection that has not failed it; when every open connection failed it, again after 30 seconds, doubling after each failed round up to 5 minutes, and at once, resetting the wait, when a new connection opens.

#### Scenario: Newest connection fails
- **WHEN** an Assistant Link has two open connections and the newest answers `event.deliver` with an error
- **THEN** the service sends the event to the other one

#### Scenario: Backoff
- **WHEN** every open connection of an Assistant Link failed the event twice in a row
- **THEN** the service waits 60 seconds before the next round

### Requirement: Send a message to the user
The service SHALL expose `POST /alp/v1/messages`, authenticated by a Link token, accepting `{"text": "<message>"}` and responding `201` with `{"message_id", "created_at"}`. It SHALL accept the request whether or not the Assistant Link is online, and SHALL NOT change its presence or last active time. Text outside the message text rules (1 to 4,000 code points, not only White_Space, no U+0000) SHALL get `422` and nothing stored.

#### Scenario: Message sent
- **WHEN** an agent posts `{"text": "Your reminder is set."}` with its Link token
- **THEN** the response is `201` with `message_id` and `created_at`
- **AND** the message appears in the Timeline of the Assistant Link's Assistant

#### Scenario: Assistant Link offline
- **WHEN** an agent posts a message while its Assistant Link is offline
- **THEN** the response is `201` and the Assistant Link stays offline

#### Scenario: Invalid text
- **WHEN** an agent posts text that is empty or only whitespace, or longer than 4,000 code points, or no string `text`, or text containing U+0000
- **THEN** the response is `422` with `text_empty`, `text_too_long`, or `invalid_params` (no string `text`, or U+0000) respectively, and nothing is stored

#### Scenario: Missing token
- **WHEN** an agent posts a message without an `Authorization` header
- **THEN** the service responds `401` with `unauthorized`

### Requirement: Idempotent send
`POST /alp/v1/messages` SHALL accept an optional `idempotency_key`, a UUIDv7 string, unique per Assistant Link; a malformed one SHALL be `422` `invalid_params`. A request repeating an `idempotency_key` SHALL respond `200` with the stored message's `{"message_id", "created_at"}` and store nothing, unless its text differs, which SHALL be `409` `idempotency_key_conflict`; if the stored message's text was deleted, the repeat SHALL respond `200` with the stored message without comparing text.

#### Scenario: Repeated idempotency_key
- **WHEN** an agent posts the same `idempotency_key` and text twice
- **THEN** the second response is `200` with the same `message_id` and the Timeline holds one message

#### Scenario: Repeated idempotency_key of a deleted message
- **WHEN** an agent posts an `idempotency_key` whose stored message's text was deleted
- **THEN** the response is `200` with the same `message_id`, whatever the text, and nothing is stored

#### Scenario: Malformed idempotency_key
- **WHEN** an agent posts an `idempotency_key` that is not a UUIDv7
- **THEN** the response is `422` with `invalid_params` and nothing is stored

#### Scenario: Reused idempotency_key with other text
- **WHEN** an agent posts an `idempotency_key` it already used with a different text
- **THEN** the response is `409` with `idempotency_key_conflict` and nothing is stored
