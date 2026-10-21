## ADDED Requirements

### Requirement: Send a message to the Assistant
The user SHALL be able to send a text message to an Assistant that has at least one Assistant Link, from a composer on the Assistant's conversation screen. The send button SHALL be disabled until the text is valid (see "Message text"). The service SHALL store every message it accepts and respond as soon as it is stored, whether or not any Assistant Link is online.

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

### Requirement: Message text
The text of a message SHALL have 1 to 4,000 Unicode code points (scalar values) and SHALL NOT consist only of Unicode White_Space characters. The app, `al`, and the service SHALL count and test it the same way.

#### Scenario: Counted in code points
- **WHEN** a text holds 4,000 emoji, each one code point
- **THEN** it is valid, and one more makes it too long

### Requirement: Delivery retention
The service SHALL keep each message of the user available for delivery to Assistant Links for 7 days after it was sent (the delivery retention), a single service setting. An Assistant Link SHALL NOT receive a message older than the delivery retention. The Timeline SHALL keep every message until the account is deleted, regardless of the delivery retention.

#### Scenario: Within the retention
- **WHEN** a message was sent 6 days ago and an Assistant Link of the Assistant connects now for the first time since
- **THEN** the Assistant Link receives it

#### Scenario: Past the retention
- **WHEN** a message was sent 8 days ago and no Assistant Link acknowledged it
- **THEN** no Assistant Link receives it
- **AND** the Timeline still shows it

### Requirement: Delivery to every Assistant Link
The service SHALL deliver each message of the user to every Assistant Link of the Assistant, in the order the messages were stored, as an event of type `message`. An Assistant Link SHALL receive only messages sent after it was paired: its cursor starts, in the pairing transaction, at the last message stored for its Assistant.

#### Scenario: Two Assistant Links
- **WHEN** the Assistant has online Assistant Links "Link 1" and "Link 2" and the user sends a message
- **THEN** both receive the message

#### Scenario: One Assistant Link is slow
- **WHEN** "Link 1" does not acknowledge a message and "Link 2" does
- **THEN** "Link 2" receives later messages while "Link 1" is still on that message

#### Scenario: Message before pairing
- **WHEN** the user sent a message before "Link 3" was paired
- **THEN** "Link 3" does not receive it

### Requirement: Delivery cursor and catch-up
The service SHALL keep one cursor per Assistant Link: the last event the Assistant Link acknowledged. It SHALL send an Assistant Link one unacknowledged event at a time, in order, and only the acknowledgement SHALL advance the cursor. When an Assistant Link connects, the service SHALL send it, in order, every event after its cursor that is within the delivery retention. The agent SHALL NOT need to remember a position.

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

### Requirement: Delivery order
The service SHALL order messages by a per-Assistant sequence assigned when they are stored, so a message committed later is never skipped by a cursor that passed a message committed earlier. An acknowledgement that arrives late SHALL NOT move the cursor back.

#### Scenario: Committed out of order
- **WHEN** two messages are being stored at once and the second to start commits first
- **THEN** the Assistant Link receives both, in the order they were stored

#### Scenario: Late acknowledgement
- **WHEN** an Assistant Link acknowledges "b" and then, late, "a"
- **THEN** its cursor stays at "b" and it does not receive "b" again

### Requirement: Message states
The app SHALL show each of the user's messages as "Sending…" while it waits for the service, "Sent" once the service stored it, and "Delivered" once at least one Assistant Link acknowledged it. Only the latest of the user's messages SHALL show "Sent" or "Delivered". The Assistant's messages SHALL show no state. The app SHALL learn that a message was delivered or expired through the notification `message.updated` on its live connection.

#### Scenario: Sent
- **WHEN** the service responds that it stored the message
- **THEN** the caption "Sending…" is replaced by "Sent"

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

### Requirement: Not Delivered messages
A message SHALL show a red exclamation mark to the right of its bubble and the red caption "Not Delivered" only for a real failure: the service rejected it or could not be reached, with no response after 15 seconds counting as not reached; or no Assistant Link acknowledged it within the delivery retention. An offline Assistant SHALL NOT make a message Not Delivered. Tapping a message the app could not send SHALL offer "Try Again" and "Cancel".

#### Scenario: Service not reachable
- **WHEN** the user sends a message and the app cannot reach the service
- **THEN** the message shows the red exclamation mark and "Not Delivered"

#### Scenario: No response
- **WHEN** the service gives no response within 15 seconds
- **THEN** the message shows "Not Delivered"

### Requirement: Expired messages
When no Assistant Link acknowledged a message within the delivery retention, the service SHALL mark it `expired` and send `message.updated`; an acknowledgement that arrives afterwards SHALL still mark it `delivered`. The expiry job SHALL run on one service node at a time. An expired message SHALL show "Not Delivered", SHALL be final, and SHALL offer no "Try Again".

#### Scenario: Expired
- **WHEN** no Assistant Link acknowledges a message within the delivery retention
- **THEN** the service marks it `expired`, sends `message.updated`, and the message shows "Not Delivered" without "Try Again"

#### Scenario: Delivered in time
- **WHEN** an Assistant Link acknowledges a message on the last day of the delivery retention
- **THEN** the message is `delivered` and never becomes `expired`

#### Scenario: Acknowledgement after expiry
- **WHEN** a message was marked `expired` and the Assistant Link's acknowledgement of it, already in flight, arrives
- **THEN** the message becomes `delivered` and the service sends `message.updated`

### Requirement: Retry a message the app could not send
Each message the app sends SHALL carry a `client_id`, which the service returns in the message so the app can match its local bubble to the stored one. The user SHALL be able to retry a message the app could not send by posting it again with the same `client_id`. If the service had stored the first request, it SHALL return the stored message with `200` and store nothing new; otherwise it SHALL store the message, at that time, so it appears at the bottom of the Timeline.

#### Scenario: Try Again succeeds
- **WHEN** the user taps a "Not Delivered" message, chooses "Try Again", and the service is reachable
- **THEN** the message becomes "Sent" and moves to the bottom of the Timeline

#### Scenario: Try Again fails
- **WHEN** the user chooses "Try Again" and the service is still not reachable
- **THEN** the message stays "Not Delivered"

#### Scenario: The first request had arrived
- **WHEN** a message is posted again with the `client_id` of a stored message
- **THEN** the service returns the stored message in its current state and stores no second one

#### Scenario: Reused client_id
- **WHEN** a message is posted with the `client_id` of a stored message but a different text or Assistant
- **THEN** the service rejects it with `409` `client_id_conflict` and stores nothing

### Requirement: Messages from the Assistant
An agent SHALL be able to send a text message to the user as its Assistant with `POST /alp/v1/messages`, whether or not its Assistant Link is online. The service SHALL store it, attribute it to the Assistant of that Link, and send the notification `message.created` to the account's open app connections. The app SHALL show it at the bottom of the open conversation within 2 seconds. The service SHALL NOT deliver it to the Assistant's Assistant Links.

#### Scenario: Message while the conversation is open
- **WHEN** the app shows the conversation with "Hermes" and the agent sends "Done."
- **THEN** a message from "Hermes" with "Done." appears at the bottom of the Timeline within 2 seconds

#### Scenario: Message while the app is closed
- **WHEN** the agent sends a message while the app is closed
- **THEN** the message appears in the Timeline the next time the user opens the conversation

#### Scenario: Message while another conversation is open
- **WHEN** the app shows the conversation with "Muse" and the agent of "Hermes" sends a message
- **THEN** the "Hermes" row in the Assistant list shows it as the latest message

#### Scenario: Other Assistant Links
- **WHEN** the agent on "Link 1" sends a message
- **THEN** the agent on "Link 2" receives no event for it

### Requirement: Message history
The service SHALL store messages per Assistant until the account is deleted and return them oldest first, the latest 50 by default and earlier ones on request.

#### Scenario: History survives relaunch
- **WHEN** the user exchanged messages with "Hermes" and relaunches the app
- **THEN** the conversation with "Hermes" shows the same messages in the same order

#### Scenario: History outlives the delivery retention
- **WHEN** the user sent a message 30 days ago
- **THEN** the conversation still shows it

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
While the Assistant is offline, the conversation screen SHALL show above the composer the notice "<name> is offline. Messages will be delivered when it connects.", and SHALL keep the composer enabled. The notice SHALL appear and disappear with the Assistant's live status.

#### Scenario: Assistant goes offline
- **WHEN** the conversation with "Hermes" is open and its only Assistant Link goes offline
- **THEN** the notice "Hermes is offline. Messages will be delivered when it connects." appears within 2 seconds

#### Scenario: Assistant comes back
- **WHEN** the notice is shown and an Assistant Link of "Hermes" comes online
- **THEN** the notice disappears within 2 seconds
