## ADDED Requirements

### Requirement: Send a message to the Assistant
The user SHALL send text from a composer, shown only while the Assistant has a paired Link.
The service SHALL store every accepted message, whether or not any Link is online.

#### Scenario: Send while offline
- **WHEN** the user sends "Remind me to call David" while every Link is offline
- **THEN** the message appears at the bottom, the composer clears, and it shows "Sent"

### Requirement: Messages need a paired Assistant Link
The service SHALL reject a message to an Assistant with no paired Link with `422` `no_paired_link` and store nothing.
`POST /alp/v1/messages` is exempt.
Checks run in this order: `401`, `404`, stored key (`200`/`409`), `422` text or params, `no_paired_link`.

#### Scenario: No paired Link
- **WHEN** a valid new message is posted to an Assistant with no paired Link
- **THEN** the service responds `422` `no_paired_link` and stores nothing

### Requirement: Message text
A text SHALL have 1 to 4,000 Unicode code points, not only White_Space, and no U+0000.
The service SHALL reject it with `422` `text_empty`, `text_too_long`, or `invalid_params` (U+0000).
The app SHALL disable send for such a text. `al` SHALL NOT check it.

#### Scenario: Counted in code points
- **WHEN** a text holds 4,000 emoji
- **THEN** it is valid, and one more is `text_too_long`

### Requirement: Delivery to every Assistant Link
The service SHALL deliver each user message as a `text_message` event to every Link of the Assistant.
A Link SHALL receive only messages stored after it was paired.
A message stored at the moment of pairing MAY arrive or not.
A message SHALL stay deliverable until acknowledged, with no time limit.

#### Scenario: Two Links, one slow
- **WHEN** "Link 1" does not acknowledge a message and "Link 2" does
- **THEN** both receive it, and "Link 2" gets later messages while "Link 1" is still on that one

#### Scenario: Message before pairing
- **WHEN** the user sent a message before "Link 3" was paired, and another after
- **THEN** "Link 3" receives only the second

### Requirement: Delivery cursor and catch-up
The service SHALL keep one cursor per Link: the last event it acknowledged.
Only an acknowledgement advances it, never backward.
On connect, the service SHALL send every deliverable event after the cursor.
Only the user's `text_message` events are deliverable, deleted ones included.

#### Scenario: Catch up and resume
- **WHEN** "Link 1" is offline while the user sends "a", "b", "c", then connects, acknowledges "a" and "b", and reconnects
- **THEN** it first receives "a", "b", "c" in order, and after the reconnect only "c"

### Requirement: Message states
The app SHALL show a user message as "Sending…" until the post is answered, "Sent" once stored, and "Delivered" once any Link acknowledged it.
Only the latest user message SHALL be captioned.
A message no Link takes stays "Sent".

#### Scenario: Sent and delivered
- **WHEN** the service stores the message, and later a Link acknowledges it
- **THEN** "Sending…" becomes "Sent", then "Delivered" within 2 seconds

#### Scenario: Stored event arrives first
- **WHEN** the stored event arrives over the live connection before the post is answered
- **THEN** the message shows "Sent"

### Requirement: Not Delivered messages
A message SHALL show a red "!" and "Not Delivered" only when its post got an error or failed on the network.
Tapping it SHALL offer "Try Again" and "Cancel".

#### Scenario: Service not reachable
- **WHEN** the user sends a message and the app cannot reach the service
- **THEN** the message shows the red "!" and "Not Delivered"

### Requirement: Retry a message the app could not send
Each app message SHALL carry an `idempotency_key`, a UUIDv7 unique per account. Otherwise `422` `invalid_params`.
"Try Again" SHALL post again with the same key.
A stored key gets the stored event with `200` and stores nothing, even if its text was deleted.
A key reused with a different text or Assistant gets `409` `idempotency_key_conflict`.

#### Scenario: The first request had arrived
- **WHEN** a message is posted again with the key of a stored message
- **THEN** the service returns the stored event, stores no second one, and the message keeps its position

#### Scenario: Reused key
- **WHEN** a message is posted with a stored key but a different text or Assistant
- **THEN** the service responds `409` `idempotency_key_conflict`

### Requirement: Messages from the Assistant
An agent SHALL send a message with `POST /alp/v1/messages`, online or not.
The service SHALL store it and send `event.created` to the account's app connections.
It SHALL NOT deliver it to the Assistant's Links.

#### Scenario: Conversation open
- **WHEN** the app shows "Hermes" and its agent sends "Done."
- **THEN** "Done." appears at the bottom within 2 seconds, and no Link of "Hermes" receives it

### Requirement: Live notification of stored messages
The service SHALL send `event.created` with `{"event": event}` to every app connection of the account for every stored `text_message`, the user's too.
`event.updated` has the same shape when a user message gets `delivered_at`.

#### Scenario: User's message on the live connection
- **WHEN** the user's app sends a message
- **THEN** every app connection receives `event.created`, and the sender matches it to its "Sending…" bubble by `idempotency_key`

### Requirement: Message history
The service SHALL keep every Timeline item as an event until the account is purged.
The app API event is `{"id", "assistant_id", "type", "sender", "link_id", "created_at", "deleted", "delivery_status", "idempotency_key", "<type>": {...}}`.
`delivery_status` is `sent` or `delivered` on the user's `text_message` events.

#### Scenario: Event shape in the app
- **WHEN** the app loads the user's message "Hi"
- **THEN** the event has `"type": "text_message"`, `"sender": "user"`, `"link_id": null`, `"deleted": false`, and `"text_message": {"text": "Hi"}`

#### Scenario: Link created event
- **WHEN** a Link is created for "Hermes", paired or not
- **THEN** the service stores a `link_created` event with no content key, and never delivers it
- **AND** an existing Link gets one on upgrade, dated at its creation

### Requirement: Event history endpoint
`GET /api/v1/assistants/:id/events` SHALL return `events` (oldest first, by `seq`) and `has_more`.
It takes `limit` (default 50, max 100) and `before`, an event id resolved to its `seq`.
An unknown `before`, or one of another Assistant, is `422` `invalid_params`. Another account's Assistant is `404`.

#### Scenario: Paging
- **WHEN** the app requests 50 events before a known event
- **THEN** it gets the 50 preceding events and `has_more`

### Requirement: Latest event in the Assistants list
Each Assistant in the list SHALL carry `latest_event`, its latest event of any type, null only with no events.

#### Scenario: Latest event
- **WHEN** the app loads the Assistants list
- **THEN** each Assistant shows its latest event, a `link_created` one included

### Requirement: Message without its text
A `text_message` whose payload was deleted SHALL stay in the Timeline with `"deleted": true` and no content key.
The app SHALL show a neutral bubble "This message was deleted".

#### Scenario: Deleted message
- **WHEN** a message's payload was deleted and the user opens the conversation
- **THEN** the Timeline shows "This message was deleted" in its place

### Requirement: Messages in the Timeline
The conversation SHALL show messages and `link_created` events together, oldest first, scrolled to the newest.
The app SHALL NOT derive "Assistant Link created" events.
It shows the latest 50, with "Load Earlier Messages" at the top when more exist.
On foreground and on every reconnect of the live connection, the app SHALL refetch the latest 50 events.
With no overlap it replaces the loaded events but keeps local unsent messages. Otherwise it merges by id.

#### Scenario: Load earlier messages
- **WHEN** the Assistant has 120 messages and the user opens the conversation
- **THEN** the latest 50 show with "Load Earlier Messages" above them
- **AND** tapping it loads the 50 before, without moving the messages on screen

#### Scenario: Missed events
- **WHEN** events arrived while the app was away
- **THEN** returning to the foreground shows them with their current states

### Requirement: Assistant offline notice
While the Assistant is offline, the conversation SHALL show above the composer "<name> is offline. Messages will be delivered when it connects." and keep the composer enabled.
It SHALL never show for an Assistant with only unpaired Links.

#### Scenario: Assistant goes offline and returns
- **WHEN** the only Link of "Hermes" goes offline, then online
- **THEN** the notice appears within 2 seconds, then disappears within 2 seconds
