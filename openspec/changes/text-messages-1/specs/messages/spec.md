## ADDED Requirements

### Requirement: Send a message to the Assistant
The user SHALL be able to send a text message to an Assistant that has at least one Assistant Link, from a composer on the Assistant's conversation screen. The send button SHALL be disabled until the text is valid (see "Message text"). The service SHALL store every message the user sends, whether or not it is delivered.

#### Scenario: Send a message
- **WHEN** the user types "Remind me to call David" in the conversation with "Hermes" and taps send
- **THEN** the message appears at the bottom of the Timeline and the composer is cleared

#### Scenario: Empty text
- **WHEN** the composer is empty or holds only spaces and line breaks
- **THEN** the send button is disabled

#### Scenario: Text too long
- **WHEN** the service receives a message of 4,001 code points
- **THEN** it rejects the request as invalid and stores nothing

### Requirement: Message text
The text of a message SHALL have 1 to 4,000 Unicode code points (scalar values) and SHALL NOT consist only of Unicode White_Space characters. The app, `al`, and the service SHALL count and test it the same way.

#### Scenario: Counted in code points
- **WHEN** a text holds 4,000 emoji, each one code point
- **THEN** it is valid, and one more makes it too long

### Requirement: Delivery to the agent
The service SHALL deliver a user's message with the request `message.deliver` to the newest open agent connection of the first online Assistant Link of the Assistant in creation order, and SHALL try the next-newest connection of that Assistant Link if the agent answers with an error or the connection closes. It SHALL NOT send one message to two connections at once, and SHALL NOT keep a failed message for later delivery.

#### Scenario: Two online Assistant Links
- **WHEN** the Assistant has online Assistant Links "Link 1" and "Link 2" and the user sends a message
- **THEN** only "Link 1" receives the message

#### Scenario: Two connections on one Assistant Link
- **WHEN** the Assistant Link has two open connections and the newest answers `message.deliver` with an error
- **THEN** the service sends the request to the other connection, and the message is `sent` if it responds with a result

#### Scenario: Nothing is delivered later
- **WHEN** a message is `failed` and the Assistant Link then comes online
- **THEN** the agent does not receive that message

### Requirement: Delivery outcome
A user's message SHALL be `sent` when the agent responds to `message.deliver` with a result, and `failed` at once when no Assistant Link is online (or the Assistant has none), and `failed` when no connection responds with a result within 10 seconds, or when every connection answers with an error, including an agent that does not support messages.

#### Scenario: Agent confirms
- **WHEN** the user sends a message while Assistant Link "laptop" is online and its agent responds to `message.deliver` with a result
- **THEN** the message is `sent`

#### Scenario: No Assistant Link online
- **WHEN** the user sends a message and none of the Assistant's Assistant Links is online, or it has none
- **THEN** the message is `failed` at once and no `message.deliver` request is sent

#### Scenario: Agent does not support messages
- **WHEN** the agent answers `message.deliver` with error `-32601` and has no other open connection
- **THEN** the message is `failed`

#### Scenario: No receipt
- **WHEN** an online agent does not respond to `message.deliver` within 10 seconds
- **THEN** the message is `failed`

### Requirement: Message states
The app SHALL show each of the user's messages as "Sending…" until the service reports the outcome. Only the user's most recent sent message SHALL show the caption "Sent". The Assistant's messages SHALL show no state.

#### Scenario: Sent
- **WHEN** the service reports that the message is `sent`
- **THEN** the caption "Sending…" is replaced by "Sent"

#### Scenario: Only the latest sent message is captioned
- **WHEN** two of the user's messages are `sent`
- **THEN** only the newer one shows "Sent"

### Requirement: Failed messages
A failed message SHALL show a red exclamation mark to the right of its bubble and the red caption "Not Delivered", and tapping it SHALL offer "Try Again" and "Cancel". The app SHALL also show a message as "Not Delivered" if it cannot reach the service or has no response after 15 seconds.

#### Scenario: Failed because the Assistant Link is offline
- **WHEN** the user sends a message while the Assistant is offline
- **THEN** the message shows the red exclamation mark and "Not Delivered"

#### Scenario: No response
- **WHEN** the service gives no response within 15 seconds
- **THEN** the message shows "Not Delivered"

### Requirement: Retry a failed message
The user SHALL be able to retry a failed message by posting it again with the same `client_id`. For a `failed` message the service SHALL atomically move it back to `sending` and attempt delivery again with the same message id and place in the Timeline, so concurrent requests start one attempt. For a `sending` or `sent` message it SHALL return the stored message and attempt nothing.

#### Scenario: Try Again succeeds
- **WHEN** the user taps a "Not Delivered" message, chooses "Try Again", and the Assistant is now online and its agent responds
- **THEN** the message becomes "Sent" in the same place in the Timeline

#### Scenario: Try Again fails
- **WHEN** the user chooses "Try Again" and the Assistant is still offline
- **THEN** the message stays "Not Delivered"

#### Scenario: Double tap
- **WHEN** two requests with the `client_id` of a failed message arrive together
- **THEN** only one delivery attempt is made

#### Scenario: Re-post of a sent message
- **WHEN** a message is posted again with the `client_id` of a message that is `sent`
- **THEN** the service returns the stored message and sends nothing

### Requirement: Matching the app's message
Each message the app sends SHALL carry a `client_id`, and the service SHALL return it in the message so the app can match its local "Sending…" or "Not Delivered" bubble to the stored one.

#### Scenario: Match after a lost response
- **WHEN** the app shows "Not Delivered" because no response arrived, and the stored message is `sent`
- **THEN** the app matches the stored message by `client_id` and shows it once, as "Sent"

### Requirement: Messages from the Assistant
An agent SHALL be able to send a text message to the user as its Assistant with `POST /alp/v1/messages`, whether or not its Assistant Link is online. The service SHALL store it, attribute it to the Assistant of that Link, and send the notification `message.created` to the account's open app connections. The app SHALL show it at the bottom of the open conversation within 2 seconds.

#### Scenario: Message while the conversation is open
- **WHEN** the app shows the conversation with "Hermes" and the agent sends "Done."
- **THEN** a message from "Hermes" with "Done." appears at the bottom of the Timeline within 2 seconds

#### Scenario: Message while the app is closed
- **WHEN** the agent sends a message while the app is closed
- **THEN** the message appears in the Timeline the next time the user opens the conversation

#### Scenario: Message while another conversation is open
- **WHEN** the app shows the conversation with "Muse" and the agent of "Hermes" sends a message
- **THEN** the "Hermes" row in the Assistant list shows it as the latest message

### Requirement: Message history
The service SHALL store messages per Assistant and return them oldest first, the latest 50 by default and earlier ones on request.

#### Scenario: History survives relaunch
- **WHEN** the user exchanged messages with "Hermes" and relaunches the app
- **THEN** the conversation with "Hermes" shows the same messages in the same order

#### Scenario: Another account's messages
- **WHEN** account A requests the messages of an Assistant that belongs to account B
- **THEN** the service responds as if the Assistant does not exist

### Requirement: Messages in the Timeline
The conversation screen SHALL show messages mixed with the "Assistant Link created" events by time, oldest first, with the newest at the bottom, and SHALL scroll to the newest on open. The user's messages SHALL be right-aligned and the Assistant's left-aligned. When earlier messages exist, the screen SHALL show "Load Earlier Messages" at the top and SHALL hide "Assistant Link created" events older than the oldest loaded message.

#### Scenario: Mixed with events
- **WHEN** "Hermes" has an Assistant Link created at 9:00, a message from the user at 9:05, and a reply at 9:06
- **THEN** the Timeline shows "Assistant Link created", the user's message, and the reply, in that order

#### Scenario: Load earlier messages
- **WHEN** the Assistant has 120 messages and the user opens the conversation
- **THEN** the latest 50 are shown with "Load Earlier Messages" above them
- **AND** tapping it loads the 50 before them without moving the messages on screen

### Requirement: Assistant offline notice
While the Assistant is offline, the conversation screen SHALL show above the composer the notice "<name> is offline. Messages can't be delivered right now.", and SHALL keep the composer enabled. The notice SHALL appear and disappear with the Assistant's live status.

#### Scenario: Assistant goes offline
- **WHEN** the conversation with "Hermes" is open and its only Assistant Link goes offline
- **THEN** the notice "Hermes is offline. Messages can't be delivered right now." appears within 2 seconds

#### Scenario: Assistant comes back
- **WHEN** the notice is shown and an Assistant Link of "Hermes" comes online
- **THEN** the notice disappears within 2 seconds
