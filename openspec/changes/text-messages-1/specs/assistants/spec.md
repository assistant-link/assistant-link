## MODIFIED Requirements

### Requirement: Assistant list is the home screen
The app SHALL open to a list of the user's Assistants, laid out like a messaging app's conversation list. Each entry SHALL show the Assistant's avatar, name, whether it is online, and its most recent event with that event's time. The most recent event is the latest event of the Assistant's Timeline (a message or "Assistant Link created"), as returned by the service. A message SHALL be shown as its text on one line, truncated, with the prefix "You: " when the user sent it; a message of the user that is Not Delivered SHALL also show a red exclamation mark before the text.

#### Scenario: Home screen shows Assistants
- **WHEN** the user opens the app and has Assistants "Hermes", "Grok Bot", and "Muse"
- **THEN** the home screen lists all three, each with avatar, name, connection status, and its most recent event

#### Scenario: Assistant without Links
- **WHEN** an Assistant has no Assistant Links
- **THEN** its entry invites the user to set up an Assistant Link instead of showing an event

#### Scenario: Empty state
- **WHEN** the user opens the app and has no Assistants
- **THEN** the home screen explains that no Assistants exist yet and offers to create one

#### Scenario: Assistant with events but no Links
- **WHEN** an Assistant has events but no Assistant Links
- **THEN** the service returns its latest event as `latest_event`, which is null only when the Assistant has no events

#### Scenario: Latest message from the Assistant
- **WHEN** the latest event of "Hermes" is its message "Done. I set a reminder." at 9:41 AM
- **THEN** the "Hermes" entry shows "Done. I set a reminder." and "9:41 AM"

#### Scenario: Latest message from the user
- **WHEN** the latest event of "Grok Bot" is the user's message "Summarize today's news"
- **THEN** the "Grok Bot" entry shows "You: Summarize today's news"

#### Scenario: Not Delivered message
- **WHEN** the latest event of "Muse" is the user's message "Are you there?" that no Assistant Link took within the delivery retention
- **THEN** the "Muse" entry shows a red exclamation mark before "You: Are you there?"

#### Scenario: Assistant Link event newer than any message
- **WHEN** an Assistant Link was created for "Hermes" after its last message
- **THEN** the "Hermes" entry shows "Assistant Link created"

### Requirement: Assistant screen
Opening an Assistant SHALL show its conversation screen, headed by a bubble with the Assistant's avatar, name, and connection status. Tapping the bubble SHALL open the Assistant's details: its avatar, name, status, and Assistant Links. While the Assistant has no Assistant Links, the conversation screen SHALL guide the user to create one. Once it has at least one, the screen SHALL show the Assistant's Timeline, which the service stores and which holds its messages and an "Assistant Link created" system event for each of its Links, written when the Link is created, oldest first. The screen SHALL show a composer below the Timeline only while the Assistant has at least one paired Assistant Link (see `messages`); until then it SHALL keep guiding setup, offering an unpaired Link's pairing text.

#### Scenario: No Links yet
- **WHEN** the user opens an Assistant that has no Assistant Links
- **THEN** the screen guides them to create an Assistant Link and hand its pairing text to their agent
- **AND** the screen has no composer

#### Scenario: Link created
- **WHEN** the user creates an Assistant Link for "Hermes"
- **THEN** the conversation for "Hermes" shows the system event "Assistant Link created" with the time it was created

#### Scenario: Only Link unpaired
- **WHEN** the user opens an Assistant whose only Assistant Link is not paired yet
- **THEN** the screen still guides setup and offers the Link's pairing text
- **AND** the screen has no composer

#### Scenario: Link paired
- **WHEN** the agent pairs the only Assistant Link of "Hermes" while its conversation is open
- **THEN** the screen shows a composer

#### Scenario: Opening the details
- **WHEN** the user taps the bubble with the Assistant's name
- **THEN** the app shows the Assistant's details with all of its Assistant Links
