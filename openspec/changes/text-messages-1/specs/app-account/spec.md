## MODIFIED Requirements

### Requirement: Log out deletes the account
The user SHALL be able to log out from the app. Because logging out cannot be undone, the app SHALL require two separate confirmations; the second SHALL state that all Assistants, Assistant Links, and history will be permanently deleted. On confirmation the service SHALL permanently delete the account and everything it owns (Assistants, Assistant Links, Link tokens, pairing codes, messages, and the rest of the history), and SHALL disconnect any agents connected on those Links. Afterwards the app SHALL return to its first-launch state.

#### Scenario: Log out after two confirmations
- **WHEN** the user taps log out, confirms, and then confirms again on the "permanently deleted" prompt
- **THEN** the service deletes the account and all its Assistants, Assistant Links, and history
- **AND** the app removes the stored credential and returns to the first-launch state with an empty Assistant list

#### Scenario: Cancel at either step
- **WHEN** the user taps log out and cancels at the first or the second confirmation
- **THEN** nothing is deleted and the app stays as it was

#### Scenario: Connected agents are disconnected
- **WHEN** the account is deleted while an agent is connected on one of its Links
- **THEN** that agent's connection is closed with the reason `account_deleted`
- **AND** its Link token is no longer accepted

#### Scenario: Deleted credential no longer works
- **WHEN** a request arrives with the credential of a deleted account
- **THEN** the service rejects it as unauthorized

#### Scenario: Messages are deleted
- **WHEN** the account is deleted after the user and the Assistant exchanged messages, some of them not yet delivered to an Assistant Link
- **THEN** none of those messages remain in the service, and no Assistant Link receives them
