## MODIFIED Requirements

### Requirement: Agent connection speaks JSON-RPC 2.0
The service SHALL accept a WebSocket connection at `GET /alp/v1/connect` authenticated by a Link token. Every text frame in either direction SHALL contain exactly one JSON-RPC 2.0 message (request, response, or notification); batches SHALL NOT be used. Service-to-agent events SHALL be JSON-RPC notifications, except an event whose delivery the service must confirm, which SHALL be a JSON-RPC request the agent answers. The service SHALL accept the agent's responses and match them to its requests by `id`; a response with an unknown or expired `id` SHALL be ignored and the connection stays open. Immediately after accepting a connection the service SHALL send the notification `connection.ready` with params `link_id`, `assistant_name`, and `protocol_version` (`"1"`). While the connection is open the Assistant Link SHALL count as online.

#### Scenario: Successful connection
- **WHEN** an agent opens `/alp/v1/connect` with a valid Link token
- **THEN** the first message it receives is `{"jsonrpc": "2.0", "method": "connection.ready", "params": {"link_id": ..., "assistant_name": ..., "protocol_version": "1"}}`
- **AND** the Assistant Link is online

## ADDED Requirements

### Requirement: Message delivery request
When the user sends a message, the service SHALL send the agent the request `message.deliver` with params `message_id` (string), `text` (string), and `sent_at` (RFC 3339 UTC timestamp). The agent SHALL confirm that it has taken the message by responding with a result object, which MAY be empty; any error response SHALL mean it did not. An agent that does not implement the method SHALL respond with `-32601`.

#### Scenario: Message delivered
- **WHEN** the user sends "Hi" to an Assistant whose Assistant Link is online
- **THEN** the agent receives `{"jsonrpc": "2.0", "id": ..., "method": "message.deliver", "params": {"message_id": ..., "text": "Hi", "sent_at": ...}}`
- **AND** the message is marked `sent` when the agent responds with `{"jsonrpc": "2.0", "id": ..., "result": {}}`

#### Scenario: Agent without message support
- **WHEN** an agent that does not implement `message.deliver` responds with `-32601`
- **THEN** the connection stays open and the message is not marked `sent`

### Requirement: Delivery errors and duplicates
An agent that cannot take a message SHALL respond to `message.deliver` with error `-32001` and `data.reason` `not_received`. A retried message SHALL carry the same `message_id`; delivery is at least once, so a reader SHALL dedupe by `message_id`.

#### Scenario: Agent cannot take the message
- **WHEN** an agent responds to `message.deliver` with error `-32001` and `data.reason` `not_received`
- **THEN** the message is not marked `sent` and the connection stays open

#### Scenario: Unknown response id
- **WHEN** the agent sends a response whose `id` matches no waiting request
- **THEN** the service ignores it and the connection stays open

### Requirement: Send a message to the user
The service SHALL expose `POST /alp/v1/messages`, authenticated by a Link token, accepting `{"text": "<message>"}` and responding `201` with `{"message_id", "sent_at"}`. It SHALL accept the request whether or not the Assistant Link is online, and SHALL NOT change its presence or last active time. The text SHALL have 1 to 4,000 Unicode code points (scalar values) and SHALL NOT consist only of Unicode White_Space characters; otherwise the response SHALL be `422` and nothing stored.

#### Scenario: Message sent
- **WHEN** an agent posts `{"text": "Your reminder is set."}` with its Link token
- **THEN** the response is `201` with `message_id` and `sent_at`
- **AND** the message appears in the Timeline of the Assistant Link's Assistant

#### Scenario: Assistant Link offline
- **WHEN** an agent posts a message while its Assistant Link is offline
- **THEN** the response is `201` and the Assistant Link stays offline

#### Scenario: Invalid text
- **WHEN** an agent posts text that is empty or only whitespace, or longer than 4,000 code points, or no string `text`
- **THEN** the response is `422` with `text_empty`, `text_too_long`, or `invalid_params` respectively, and nothing is stored

#### Scenario: Missing token
- **WHEN** an agent posts a message without an `Authorization` header
- **THEN** the service responds `401` with `unauthorized`

### Requirement: Idempotent message from the agent
`POST /alp/v1/messages` SHALL accept an optional string `client_id`, unique per Assistant Link. Repeating it SHALL respond `200` with the stored message's `{"message_id", "sent_at"}` and store no duplicate.

#### Scenario: Repeated client_id
- **WHEN** an agent posts a message with a `client_id` it already used
- **THEN** the response is `200` with the stored message and no second message is stored
