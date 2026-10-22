## ADDED Requirements

### Requirement: Send a message to the Assistant
The user SHALL be able to send a text message to an Assistant that has at least one paired Assistant Link, from a composer on the Assistant's conversation screen, shown only while one is paired. The send button SHALL be disabled until the text is valid (see "Message text"). The service SHALL store every message it accepts and respond as soon as it is stored, whether or not any Assistant Link is online.

#### Scenario: Send a message
- **WHEN** the user types "Remind me to call David" in the conversation with "Hermes" and taps send
- **THEN** the message appears at the bottom of the Timeline and the composer is cleared

#### Scenario: Assistant offline
- **WHEN** the user sends a message while every Assistant Link of the Assistant is offline
- **THEN** the service stores it and responds, and the message shows "Sent"

#### Scenario: Empty text
- **WHEN** the composer is empty or holds only spaces and line breaks
- **THEN** the send button is disabled

#### Scenario: Text too long
- **WHEN** the service receives a message of 4,001 code points
- **THEN** it rejects the request as invalid and stores nothing

### Requirement: Messages need a paired Assistant Link
The service SHALL reject a message to an Assistant with no paired Assistant Link (no Links, or only unpaired ones) with `422` `no_paired_link` and store nothing, checking inside the storing transaction, in the order of the scenario "Order of checks". `no_paired_link` does not apply to `POST /alp/v1/messages`, because a Link token implies a paired Link.

#### Scenario: Order of checks
- **WHEN** the service receives a post to `POST /api/v1/assistants/:id/messages`
- **THEN** it checks authentication (`401`), then an unknown Assistant (`404`), then an `idempotency_key` already stored for the account (the idempotent repeat: `200` with the stored event, or `409` `idempotency_key_conflict`), then invalid params or text (`422` `invalid_params`, `text_empty`, `text_too_long`), and only then `no_paired_link` (`422`)

#### Scenario: No paired Assistant Link
- **WHEN** the service receives a valid new message for an Assistant with no Assistant Links, or only unpaired ones
- **THEN** it responds `422` `no_paired_link` and stores nothing

#### Scenario: Repeat after the Links changed
- **WHEN** a message was stored and its `idempotency_key` is posted again after the Assistant has lost its paired Assistant Links
- **THEN** the service responds `200` with the stored event, not `no_paired_link`

#### Scenario: Invalid text before no paired Link
- **WHEN** the service receives an empty text for an Assistant with no paired Assistant Link
- **THEN** it responds `422` `text_empty`

### Requirement: Message text
The text of a message SHALL have 1 to 4,000 Unicode code points (scalar values) and SHALL NOT consist only of Unicode White_Space characters. The service SHALL enforce these rules; the app SHALL disable the send button for text that breaks them, counting code points the same way; `al` SHALL NOT check the length and SHALL pass the text to the service unchanged.

#### Scenario: NUL character
- **WHEN** a text contains U+0000
- **THEN** the service responds `422` `invalid_params` on both endpoints and stores nothing

#### Scenario: Counted in code points
- **WHEN** a text holds 4,000 emoji, each one code point
- **THEN** it is valid, and one more makes it too long

### Requirement: Delivery to every Assistant Link
The service SHALL deliver each message of the user to every Assistant Link of the Assistant, in the order the messages were stored, as an event of type `text_message`. An Assistant Link SHALL receive only messages sent after it was paired: its cursor starts, in the pairing transaction, at the Assistant's last event sequence. An unpaired Assistant Link has no token and no connection, so it receives nothing.

#### Scenario: Two Assistant Links
- **WHEN** the Assistant has online Assistant Links "Link 1" and "Link 2" and the user sends a message
- **THEN** both receive the message

#### Scenario: One Assistant Link is slow
- **WHEN** "Link 1" does not acknowledge a message and "Link 2" does
- **THEN** "Link 2" receives later messages while "Link 1" is still on that message

#### Scenario: Message before pairing
- **WHEN** the user sent a message before "Link 3" was paired
- **THEN** "Link 3" does not receive it

#### Scenario: Message after pairing
- **WHEN** the user sends a message after "Link 3" was paired
- **THEN** "Link 3" receives it

#### Scenario: Message at the moment of pairing
- **WHEN** the user sends a message at the same moment "Link 3" is paired
- **THEN** "Link 3" may or may not receive it, and either outcome is correct

### Requirement: Delivery cursor and catch-up
The service SHALL keep one cursor per Assistant Link: the last event the Assistant Link acknowledged. It SHALL send an Assistant Link one unacknowledged event at a time, in order, and only the acknowledgement SHALL advance the cursor. When an Assistant Link connects, the service SHALL send it, in order, every deliverable event after its cursor. The agent SHALL NOT need to remember a position.

#### Scenario: Catch up after being offline
- **WHEN** "Link 1" is offline while the user sends "a", "b", and "c", and then connects
- **THEN** it receives "a", then "b", then "c", each after it acknowledged the one before

#### Scenario: Resume where it left off
- **WHEN** "Link 1" acknowledged "a" and "b", disconnects, and reconnects
- **THEN** it receives "c" next and not "a" or "b" again

#### Scenario: Independent cursors
- **WHEN** "Link 1" acknowledged "a", "b", and "c" and "Link 2" only "a"
- **THEN** after "Link 2" reconnects it receives "b", and "Link 1" receives nothing

#### Scenario: Several connections of one Assistant Link
- **WHEN** an Assistant Link has two open connections and the user sends a message
- **THEN** only the newest connection receives it, and the other receives it only if the newest closes or answers with an error before acknowledging

### Requirement: Deliverable events
The service SHALL deliver only the user's `text_message` events, including one whose content was deleted (see "Message without its text"). Events that are not deliverable, such as `link_created`, SHALL be skipped by the cursor. The cursor SHALL move only by acknowledgement.

#### Scenario: Link created events are skipped
- **WHEN** "Link 1" has a cursor before a `link_created` event and a later message
- **THEN** it receives the message and never the `link_created` event

### Requirement: Delivery order
The service SHALL order events by a per-Assistant sequence assigned when they are stored, under a per-Assistant lock held until commit, so an event committed later is never skipped by a cursor that passed an event committed earlier. An acknowledgement that arrives late SHALL NOT move the cursor back.

#### Scenario: Committed out of order
- **WHEN** two messages are being stored at once and the second to start commits first
- **THEN** the Assistant Link receives both, in the order they were stored

#### Scenario: Late acknowledgement
- **WHEN** an Assistant Link acknowledges "b" and then, late, "a"
- **THEN** its cursor stays at "b" and it does not receive "b" again

### Requirement: Message states
The app SHALL show each of the user's messages as "Sending…" until the post to the service is answered, "Sent" once the service stored it, and "Delivered" once at least one Assistant Link acknowledged it. Only the latest of the user's messages SHALL show "Sent" or "Delivered". The Assistant's messages SHALL show no state. The app SHALL learn of delivery through `event.updated`, and of storage through `event.created`, on its live connection.

#### Scenario: Sent
- **WHEN** the service responds that it stored the message
- **THEN** the caption "Sending…" is replaced by "Sent"

#### Scenario: Stored event arrives first
- **WHEN** the message is still "Sending…" and its stored event arrives over the live connection before the post is answered
- **THEN** the message shows "Sent"

#### Scenario: Delivered
- **WHEN** an Assistant Link acknowledges the message while the conversation is open
- **THEN** the caption becomes "Delivered" within 2 seconds

#### Scenario: Delivered to one of several
- **WHEN** "Link 1" acknowledges the message and "Link 2" has not
- **THEN** the message shows "Delivered"

#### Scenario: Only the latest message is captioned
- **WHEN** two of the user's messages are delivered
- **THEN** only the newer one shows "Delivered"

#### Scenario: State changed while the app was away
- **WHEN** a message became delivered while the app was closed and the user opens the conversation
- **THEN** it shows its current state

#### Scenario: Never taken
- **WHEN** the service stored a message and no Assistant Link has ever acknowledged it
- **THEN** it keeps showing "Sent"

#### Scenario: First acknowledgement wins
- **WHEN** "Link 1" and then "Link 2" acknowledge the same message
- **THEN** `delivered_at` keeps the time of "Link 1"'s acknowledgement and `event.updated` is sent once, while each Link's own cursor advances past the message

### Requirement: Not Delivered messages
A message SHALL show a red exclamation mark to the right of its bubble and the red caption "Not Delivered" only for a real failure: the service answered the post with an error, or the post failed for a real network reason (connection lost, the system request timeout). An offline Assistant, or a stored message no Assistant Link has taken, SHALL NOT make a message Not Delivered. Tapping a message the app could not send SHALL offer "Try Again" and "Cancel".

#### Scenario: Service not reachable
- **WHEN** the user sends a message and the app cannot reach the service
- **THEN** the message shows the red exclamation mark and "Not Delivered"

#### Scenario: Error response
- **WHEN** the service answers the post with an error
- **THEN** the message shows "Not Delivered" with "Try Again"

#### Scenario: Slow response
- **WHEN** the service takes a long time to answer and the system request has not timed out
- **THEN** the message keeps showing "Sending…"

### Requirement: Retry a message the app could not send
Each message the app sends SHALL carry an `idempotency_key`, a UUIDv7 string the service returns in the message so the app can match its local bubble to the stored one. The user SHALL be able to retry a message the app could not send by posting it again with the same `idempotency_key`. If the service had stored the first request, it SHALL return the stored message with `200` and store nothing new, even if its text was deleted (same Assistant, text not compared); otherwise it SHALL store it then.

#### Scenario: Try Again succeeds
- **WHEN** the user taps a "Not Delivered" message, chooses "Try Again", and the service is reachable
- **THEN** the message becomes "Sent"
- **AND** if the service had not stored it before, it is stored now and appears at the bottom of the Timeline

#### Scenario: Try Again fails
- **WHEN** the user chooses "Try Again" and the service is still not reachable
- **THEN** the message stays "Not Delivered"

#### Scenario: The first request had arrived
- **WHEN** a message is posted again with the `idempotency_key` of a stored message
- **THEN** the service returns the stored message in its current state and stores no second one
- **AND** the message keeps its original position in the Timeline

#### Scenario: Missing or malformed idempotency_key
- **WHEN** the app endpoint receives a message without an `idempotency_key`, or one that is not a UUIDv7
- **THEN** the service responds `422` `invalid_params` and stores nothing

#### Scenario: Reused idempotency_key
- **WHEN** a message is posted with the `idempotency_key` of a stored message but a different text or Assistant
- **THEN** the service rejects it with `409` `idempotency_key_conflict` and stores nothing

#### Scenario: Reused idempotency_key of a deleted message
- **WHEN** a message is posted with the `idempotency_key` of a stored message whose text was deleted, for the same Assistant
- **THEN** the service responds `200` with the stored (deleted) event without comparing text, and stores nothing
- **AND** for another Assistant it responds `409` `idempotency_key_conflict`

### Requirement: Messages from the Assistant
An agent SHALL be able to send a text message to the user as its Assistant with `POST /alp/v1/messages`, whether or not its Assistant Link is online. The service SHALL store it, attribute it to the Assistant of that Link, and send the notification `event.created` to the account's open app connections. The app SHALL show it at the bottom of the open conversation within 2 seconds. The service SHALL NOT deliver it to the Assistant's Assistant Links.

#### Scenario: Message while the conversation is open
- **WHEN** the app shows the conversation with "Hermes" and the agent sends "Done."
- **THEN** a message from "Hermes" with "Done." appears at the bottom of the Timeline within 2 seconds

#### Scenario: Message while the app is closed
- **WHEN** the agent sends a message while the app is closed
- **THEN** the message appears in the Timeline the next time the user opens the conversation

#### Scenario: Message while another conversation is open
- **WHEN** the app shows the conversation with "Muse" and the agent of "Hermes" sends a message
- **THEN** the "Hermes" row in the Assistant list shows it as the latest event

#### Scenario: Other Assistant Links
- **WHEN** the agent on "Link 1" sends a message
- **THEN** the agent on "Link 2" receives no event for it

### Requirement: Live notification of stored messages
The service SHALL send `event.created` for every stored `text_message`, the user's too, to every app connection of the account. The sending app SHALL match it to its local bubble by `idempotency_key`; other app connections SHALL append it.

#### Scenario: User's message on the live connection
- **WHEN** the user's app sends a message and the service stores it
- **THEN** every app connection of the account receives `event.created` for it; the sending app matches it to its "Sending…" bubble by `idempotency_key` and the others append it

### Requirement: Message history
The service SHALL store every item of an Assistant's Timeline as an event until the account is purged and return them oldest first, the latest 50 by default and earlier ones on request. Events use the nested format: `id`, `type`, `created_at`, `deleted` (always present), and the content under a key named after the type; the app API adds `assistant_id`, `sender`, `link_id`, `delivery_status`, and `idempotency_key`.

#### Scenario: Event shape in the app
- **WHEN** the app loads the history and it holds the user's message "Hi"
- **THEN** the event is `{"id", "assistant_id", "type": "text_message", "sender": "user", "link_id": null, "created_at", "deleted": false, "delivery_status", "idempotency_key", "text_message": {"text": "Hi"}}`

#### Scenario: Deleted and Link events have no content key
- **WHEN** the history holds a deleted message and an "Assistant Link created" event
- **THEN** the deleted message has `"deleted": true` and no `text_message` key, and the Link event has no content key

#### Scenario: Link created event in the history
- **WHEN** an Assistant Link is created for "Hermes"
- **THEN** the service stores an "Assistant Link created" event, written in the same transaction as the Link, whether or not the Link is paired yet, and the history returns it

#### Scenario: Existing Links
- **WHEN** the service is upgraded and "Hermes" already has an Assistant Link
- **THEN** the history of "Hermes" contains an "Assistant Link created" event with the time the Link was created

#### Scenario: History survives relaunch
- **WHEN** the user exchanged messages with "Hermes" and relaunches the app
- **THEN** the conversation with "Hermes" shows the same messages in the same order

#### Scenario: Another account's messages
- **WHEN** account A requests the messages of an Assistant that belongs to account B
- **THEN** the service responds as if the Assistant does not exist

### Requirement: Message without its text
A `text_message` event whose content was deleted on its own SHALL stay in the Timeline as a deleted event, with `"deleted": true` and no content key. It SHALL be delivered to Assistant Links like any other event, and the app SHALL show it as a neutral placeholder bubble "This message was deleted". The cursor SHALL move only by acknowledgement.

#### Scenario: Deleted message in the history
- **WHEN** the content of a message was deleted and the user opens the conversation
- **THEN** the Timeline shows the placeholder bubble "This message was deleted" in its place

#### Scenario: Agent receives a deleted event
- **WHEN** a connecting Assistant Link has a deleted message after its cursor
- **THEN** it receives that event with `"deleted": true` and no `text_message` key, and then the messages after it, each after the acknowledgement of the one before

### Requirement: Messages in the Timeline
The conversation screen SHALL show the events returned by the history, messages and "Assistant Link created" events together, oldest first, with the newest at the bottom, and SHALL scroll to the newest on open. The app SHALL NOT derive "Assistant Link created" events itself. The user's messages SHALL be right-aligned and the Assistant's left-aligned. When earlier events exist, the screen SHALL show "Load Earlier Messages" at the top.

#### Scenario: Mixed with events
- **WHEN** "Hermes" has an Assistant Link created at 9:00, a message from the user at 9:05, and a reply at 9:06
- **THEN** the Timeline shows "Assistant Link created", the user's message, and the reply, in that order

#### Scenario: Load earlier messages
- **WHEN** the Assistant has 120 messages and the user opens the conversation
- **THEN** the latest 50 are shown with "Load Earlier Messages" above them
- **AND** tapping it loads the 50 before them without moving the messages on screen

### Requirement: Assistant offline notice
While the Assistant is offline, the conversation screen SHALL show above the composer the notice "<name> is offline. Messages will be delivered when it connects.", and SHALL keep the composer enabled. The notice SHALL appear and disappear with the Assistant's live status. The notice SHALL never appear for an Assistant with only unpaired Links, which has no composer.

#### Scenario: Assistant goes offline
- **WHEN** the conversation with "Hermes" is open and its only Assistant Link goes offline
- **THEN** the notice "Hermes is offline. Messages will be delivered when it connects." appears within 2 seconds

#### Scenario: Assistant comes back
- **WHEN** the notice is shown and an Assistant Link of "Hermes" comes online
- **THEN** the notice disappears within 2 seconds

#### Scenario: Only unpaired Links
- **WHEN** the Assistant's only Assistant Link is not paired
- **THEN** the screen shows no composer and no offline notice
