# Spec Delta

## Purpose

Lets the user create the Assistants they talk to (each with a name and avatar) and see them, with their connection status, as the app's home screen.

## ADDED Requirements

### Requirement: Create an Assistant
The user SHALL be able to create an Assistant by giving it a name (1 to 50 characters, not only whitespace) and choosing one of 10 preset avatars. Each preset avatar SHALL have a stable identifier (`avatar-1` to `avatar-10`); until final assets are defined, each SHALL be shown as a filled circle in its own distinct color. One preset SHALL be preselected so the user only has to enter a name. The Assistant SHALL be stored by the service under the user's account.

#### Scenario: Create with a chosen avatar
- **WHEN** the user creates an Assistant named "Hermes" and picks the third preset avatar
- **THEN** the Assistant "Hermes" appears in the Assistant list with that avatar
- **AND** it is still there, with the same avatar, after the app is relaunched

#### Scenario: Default avatar preselected
- **WHEN** the user creates an Assistant named "Muse" without changing the avatar
- **THEN** the Assistant is created with the preselected preset avatar

#### Scenario: Invalid name is rejected
- **WHEN** the user tries to create an Assistant with an empty or whitespace-only name, or a name longer than 50 characters
- **THEN** the Assistant is not created and the user is told why

#### Scenario: Unknown avatar is rejected
- **WHEN** the service receives a create request with an avatar identifier outside `avatar-1` to `avatar-10`
- **THEN** the Assistant is not created and the request fails as invalid

### Requirement: Assistant list is the home screen
The app SHALL open to a list of the user's Assistants, laid out like a messaging app's conversation list. Each entry SHALL show the Assistant's avatar, name, whether it is online, and its most recent event with that event's time.

#### Scenario: Home screen shows Assistants
- **WHEN** the user opens the app and has Assistants "Hermes", "Grok Bot", and "Muse"
- **THEN** the home screen lists all three, each with avatar, name, connection status, and its most recent event

#### Scenario: Assistant without Links
- **WHEN** an Assistant has no Assistant Links
- **THEN** its entry invites the user to set up a Link instead of showing an event

#### Scenario: Empty state
- **WHEN** the user opens the app and has no Assistants
- **THEN** the home screen explains that no Assistants exist yet and offers to create one

### Requirement: Assistant screen
Opening an Assistant SHALL show its conversation screen, headed by a bubble with the Assistant's avatar, name, and connection status. Tapping the bubble SHALL open the Assistant's details: its avatar, name, status, and Assistant Links. While the Assistant has no Assistant Links, the conversation screen SHALL guide the user to create one. Once it has at least one, the screen SHALL show the Assistant's conversation, which in this slice holds an "Assistant Link created" system event for each of its Links, oldest first.

#### Scenario: No Links yet
- **WHEN** the user opens an Assistant that has no Assistant Links
- **THEN** the screen guides them to create an Assistant Link and hand its pairing text to their agent

#### Scenario: Link created
- **WHEN** the user creates an Assistant Link for "Hermes"
- **THEN** the conversation for "Hermes" shows the system event "Assistant Link created" with the time it was created

#### Scenario: Opening the details
- **WHEN** the user taps the bubble with the Assistant's name
- **THEN** the app shows the Assistant's details with all of its Assistant Links

### Requirement: Assistant connection status
An Assistant's connection status SHALL be "online" when at least one of its Assistant Links is online, and "offline" otherwise, including when it has no Assistant Links.

#### Scenario: One Link online
- **WHEN** an Assistant has two Assistant Links and one of them is online
- **THEN** the Assistant is shown as online

#### Scenario: No Links
- **WHEN** an Assistant has no Assistant Links
- **THEN** the Assistant is shown as offline
