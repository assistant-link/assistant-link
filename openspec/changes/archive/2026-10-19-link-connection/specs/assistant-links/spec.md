# Spec Delta

## Purpose

Connects an Assistant to specific agent installations: the user creates an Assistant Link, hands pairing text to their agent, and then sees, for every Link, whether that agent is connected and when it was last active.

## ADDED Requirements

### Requirement: Create an Assistant Link
The user SHALL be able to create an Assistant Link for an Assistant in one step, from the Assistant's screen (while it has no Links) or from its details, without being asked for a label, so the path to connecting an agent stays short. A Link without a label SHALL be shown with a default name by its position ("Link 1", "Link 2", …). An Assistant MAY have any number of Assistant Links.

#### Scenario: Create a Link
- **WHEN** the user opens the Assistant "Hermes", which has no Links, and creates an Assistant Link
- **THEN** a new Assistant Link "Link 1" appears in the details of "Hermes" with status "not paired"
- **AND** the app shows pairing text for it
- **AND** the conversation for "Hermes" shows the system event "Assistant Link created"

### Requirement: Paste-to-agent pairing text
For an Assistant Link that is not paired yet, the app SHALL show pairing text meant to be pasted to the agent as-is, with a one-tap copy action. The pairing text SHALL be reachable from the Link in the Assistant's details and from its "Assistant Link created" event. The pairing text SHALL contain: the URL of the agent install instructions, the service URL, the pairing code, and when the code expires.

#### Scenario: Copy pairing text
- **WHEN** the user taps copy on the pairing text
- **THEN** the full pairing text is placed on the clipboard
- **AND** it includes the install instructions URL, service URL, pairing code, and expiry time

### Requirement: Pairing code lifetime
A pairing code SHALL be single-use, SHALL expire 15 minutes after it is issued, and SHALL be easy to type (8 characters from an alphabet without ambiguous characters, case-insensitive). While an Assistant Link is not paired, the user SHALL be able to generate a new pairing code for it; generating one SHALL invalidate any earlier unused code for that Link. Once a Link is paired, no new pairing code SHALL be issued for it.

#### Scenario: Expired code
- **WHEN** an agent submits a pairing code 16 minutes after it was issued
- **THEN** pairing fails with an "expired" error and no Link token is issued

#### Scenario: Code used twice
- **WHEN** an agent submits a pairing code that was already used successfully
- **THEN** pairing fails with an "invalid code" error

#### Scenario: New code replaces old
- **WHEN** the user generates a new pairing code for an unpaired Link that still has an unused code
- **THEN** the older code no longer works and the new one does

#### Scenario: Paired Link gets no new code
- **WHEN** a pairing code is requested for a Link that is already paired
- **THEN** the request is rejected and no code is issued

### Requirement: Pairing issues a Link token
A successful pairing SHALL pair exactly one Assistant Link and issue a Link token that authenticates the agent as that Link. Pairing SHALL NOT affect any other Assistant Link or its token. A Link token SHALL stay valid until the account that owns the Link is deleted.

#### Scenario: Successful pairing
- **WHEN** an agent submits a valid, unexpired pairing code
- **THEN** the agent receives a Link token for that Assistant Link
- **AND** the Link's status in the app changes from "not paired" to "offline" (or "online" once the agent connects)

#### Scenario: Pairing a Link leaves other Links untouched
- **WHEN** the Assistant "Hermes" has a paired, connected Link "laptop" and the user pairs a new Link "cloud"
- **THEN** "laptop" stays connected and its Link token keeps working
- **AND** both Links are listed under "Hermes"

### Requirement: Link presence
An Assistant Link SHALL be "online" while at least one agent connection authenticated with its Link token is open, and "offline" otherwise. When a connection closes cleanly the Link SHALL become offline immediately; when a connection is lost without closing, the Link SHALL become offline within 60 seconds.

#### Scenario: Agent connects
- **WHEN** an agent opens a connection with a valid Link token
- **THEN** the Link becomes online

#### Scenario: Agent disconnects cleanly
- **WHEN** the agent's only connection closes cleanly
- **THEN** the Link becomes offline immediately

#### Scenario: Agent vanishes
- **WHEN** the agent host loses network without closing its connection
- **THEN** the Link becomes offline within 60 seconds

### Requirement: Link list with presence and last active time
The Assistant's details SHALL list all of its Assistant Links. Each entry SHALL show the Link's label (or a default name when none was given), its status ("not paired", "online", or "offline"), and when it was last active. "Last active" SHALL be the most recent time an agent connection for that Link was open: shown as "now" while online, as a time (for example "5 min ago") when offline, and as "never" if no agent has connected yet.

#### Scenario: Several Links listed
- **WHEN** the Assistant "Hermes" has Links "laptop" (online), "cloud" (offline, disconnected 2 hours ago), and "spare" (not paired)
- **THEN** the details of "Hermes" list all three: "laptop" online, active now; "cloud" offline, last active about 2 hours ago; "spare" not paired, never active

#### Scenario: Last active updates on disconnect
- **WHEN** the agent on Link "laptop" disconnects
- **THEN** "laptop" shows offline with a last active time of the disconnect

### Requirement: Live status in the app
While the app is open, changes to a Link's status SHALL appear in the app within 2 seconds, without the user refreshing. When the app returns to the foreground it SHALL show current statuses and last active times.

#### Scenario: Status updates live
- **WHEN** the app is showing the Assistant list and the agent for "Hermes" connects
- **THEN** "Hermes" changes to online within 2 seconds without user action

#### Scenario: Returning to the app
- **WHEN** the app returns to the foreground after an agent disconnected in the background
- **THEN** the app shows the Link and its Assistant as offline, with the Link's updated last active time
