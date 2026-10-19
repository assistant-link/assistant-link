# alp Specification

## Purpose

Defines the public, versioned Assistant Link Protocol (ALP) that any agent can implement directly to pair and connect, built on established standards (HTTP, WebSocket, JSON-RPC 2.0), so integrations work without the `al` CLI and keep working as the protocol evolves.

## Requirements

### Requirement: Versioned base path
All ALP endpoints SHALL live under the base path `/alp/v1`. Changes within v1 SHALL be additive only (new endpoints, new methods and notifications, new optional fields). Anything that would break an existing v1 agent SHALL go under a new version path.

#### Scenario: v1 endpoints
- **WHEN** an agent calls the pairing endpoint or opens the agent connection
- **THEN** it uses paths under `/alp/v1`

### Requirement: Pairing endpoint
The service SHALL expose `POST /alp/v1/pair` accepting a JSON body `{"code": "<pairing code>"}`. The code SHALL be matched case-insensitively and ignoring spaces and hyphens. On success it SHALL respond `200` with a JSON body containing at least `link_id`, `assistant_name`, and `token` (the Link token).

#### Scenario: Valid code
- **WHEN** an agent posts a valid, unexpired pairing code
- **THEN** the response is `200` with `link_id`, `assistant_name`, and `token`

#### Scenario: Code typed with different formatting
- **WHEN** an agent posts the code `k7qm-2xpa` for issued code `K7QM2XPA`
- **THEN** pairing succeeds

#### Scenario: Invalid or expired code
- **WHEN** an agent posts an unknown, used, or expired code
- **THEN** the response is an HTTP error with code `invalid_code` or `expired_code`

### Requirement: HTTP error format
ALP HTTP errors (including a rejected WebSocket upgrade) SHALL use an appropriate 4xx/5xx status and a JSON body `{"error": {"code": "<reason>", "message": "<human readable>"}}`, where `code` is a stable snake_case identifier agents can match on.

#### Scenario: Error body
- **WHEN** any ALP HTTP request fails
- **THEN** the body contains `error.code` and `error.message`

### Requirement: Link token authentication
Agents SHALL authenticate ALP requests other than pairing with the header `Authorization: Bearer <Link token>`. Requests with a missing or unknown token, or the token of a Link whose account was deleted, SHALL be rejected with status `401` and error code `unauthorized`.

#### Scenario: Missing token
- **WHEN** an agent opens the agent connection without an `Authorization` header
- **THEN** the service rejects it with `401` and `unauthorized`

#### Scenario: Token no longer valid
- **WHEN** an agent uses the Link token of a Link whose account was deleted
- **THEN** the service rejects it with `401` and `unauthorized`

### Requirement: Agent connection speaks JSON-RPC 2.0
The service SHALL accept a WebSocket connection at `GET /alp/v1/connect` authenticated by a Link token. Every text frame in either direction SHALL contain exactly one JSON-RPC 2.0 message (request, response, or notification); batches SHALL NOT be used. Service-to-agent events SHALL be JSON-RPC notifications. Immediately after accepting a connection the service SHALL send the notification `connection.ready` with params `link_id`, `assistant_name`, and `protocol_version` (`"1"`). While the connection is open the Assistant Link SHALL count as online.

#### Scenario: Successful connection
- **WHEN** an agent opens `/alp/v1/connect` with a valid Link token
- **THEN** the first message it receives is `{"jsonrpc": "2.0", "method": "connection.ready", "params": {"link_id": ..., "assistant_name": ..., "protocol_version": "1"}}`
- **AND** the Assistant Link is online

### Requirement: JSON-RPC errors
The service SHALL answer malformed or unsupported messages with standard JSON-RPC 2.0 error responses and SHALL keep the connection open: `-32700` for invalid JSON, `-32600` for an invalid request (including a batch), `-32601` for an unknown method, and `-32602` for invalid params. ALP-specific errors SHALL use codes in the range `-32000` to `-32099` and SHALL include a stable snake_case reason in `error.data.reason`.

#### Scenario: Unknown method
- **WHEN** an agent sends `{"jsonrpc": "2.0", "id": 1, "method": "something.new"}`
- **THEN** the service responds with an error for `id` 1 with code `-32601`
- **AND** the connection stays open

#### Scenario: Invalid JSON
- **WHEN** an agent sends a frame that is not valid JSON
- **THEN** the service responds with an error with code `-32700` and `id` null
- **AND** the connection stays open

### Requirement: Forward compatibility
Agents SHALL ignore notifications whose method they do not recognize and fields they do not recognize. When the service sends an agent a request for a method the agent does not implement, the agent SHALL respond with error `-32601`.

#### Scenario: Unknown notification from the service
- **WHEN** a v1 agent receives a notification with a method added in a later v1 revision
- **THEN** the agent ignores it and the connection continues normally

### Requirement: Liveness
The service SHALL send WebSocket ping frames on the agent connection at least every 25 seconds, and SHALL treat the connection as lost if no pong or other frame arrives from the agent within 60 seconds of a ping. Agents SHALL answer pings as the WebSocket standard requires.

#### Scenario: Unresponsive agent
- **WHEN** an agent stops responding to pings
- **THEN** the service closes the connection within 60 seconds and the Link becomes offline

### Requirement: Connection closed by the service
When the service closes an agent connection on purpose, it SHALL first send the notification `connection.closing` with a `reason` param (a stable snake_case identifier, for example `account_deleted`), then close the WebSocket.

#### Scenario: Account deleted while connected
- **WHEN** the account owning the Link is deleted while an agent is connected
- **THEN** the agent receives `connection.closing` with reason `account_deleted`
- **AND** the connection is closed
