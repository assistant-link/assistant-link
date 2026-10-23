## MODIFIED Requirements

### Requirement: Assistant list is the home screen
The app SHALL open to a list of the user's Assistants, laid out like a messaging app's conversation list.
Each entry SHALL show the Assistant's avatar, name, whether it is online, and its latest event (a message or "Assistant Link created") with its time, as returned by the service.
A message SHALL show its text on one line, truncated, with the prefix "You: " when the user sent it.
A user message that failed in the app and was never stored SHALL also show a red "!" before the text.

#### Scenario: Home screen shows Assistants
- **WHEN** the user opens the app and has Assistants "Hermes", "Grok Bot", and "Muse"
- **THEN** the home screen lists all three, each with avatar, name, connection status, and its latest event

#### Scenario: Assistant without Links
- **WHEN** an Assistant has no Assistant Links
- **THEN** its entry invites the user to set up an Assistant Link instead of showing an event

#### Scenario: Empty state
- **WHEN** the user opens the app and has no Assistants
- **THEN** the home screen explains that no Assistants exist yet and offers to create one

#### Scenario: Latest message from the Assistant or the user
- **WHEN** the latest event of "Hermes" is its message "Done." and that of "Grok Bot" is the user's "Summarize today's news"
- **THEN** the entries show "Done." and "You: Summarize today's news"

#### Scenario: Message that failed in the app
- **WHEN** the user's latest message to "Muse" failed to send and was never stored
- **THEN** the "Muse" entry shows a red "!" before "You: " and the text

### Requirement: Assistant screen
Opening an Assistant SHALL show its conversation screen, headed by a bubble with the Assistant's avatar, name, and connection status.
Tapping the bubble SHALL open the Assistant's details: avatar, name, status, and Links.
While the Assistant has no Links, the screen SHALL guide the user to create one.
Once it has one, the screen SHALL show the stored Timeline (see `messages`).
The screen SHALL show a composer only while the Assistant has a paired Link.
Until then it SHALL keep guiding setup.

#### Scenario: No Links yet
- **WHEN** the user opens an Assistant with no Links
- **THEN** the screen guides them to create a Link and hand its pairing text to their agent, with no composer

#### Scenario: Link created
- **WHEN** the user creates a Link for "Hermes"
- **THEN** the conversation shows "Assistant Link created" with the creation time

#### Scenario: Link paired
- **WHEN** the only Link is unpaired and the agent pairs it
- **THEN** the screen shows a composer

#### Scenario: Opening the details
- **WHEN** the user taps the bubble with the Assistant's name
- **THEN** the app shows the Assistant's details with all of its Links
