## MODIFIED Requirements

### Requirement: Log out deletes the account
The user SHALL be able to log out from the app. Because logging out cannot be undone, the app SHALL require two separate confirmations; the second SHALL state that all Assistants, Assistant Links, and history are deleted, that this can't be undone, and that the service permanently erases the data after 60 days. Logging out SHALL soft delete the account: the service SHALL record when it was deleted (`deleted_at`) and keep its data, and from then on the account SHALL behave as deleted. Its device credentials and Link tokens SHALL be rejected as unauthorized, its pairing codes SHALL be rejected like an unknown code, web sessions and magic-link tokens of users whose only account it is SHALL stop working at once, its data (Assistants, Timeline events with their message texts, and the rest of the history) SHALL NOT be readable, postable, or deliverable to any Assistant Link, and the service SHALL disconnect the agents and app connections of the account. Once `deleted_at` is older than the deletion grace period, a single service setting that defaults to 60 days, the service SHALL permanently delete the account, everything it owns, and every user whose only account it was; it SHALL NOT purge an account within the grace period, and the user SHALL NOT be able to undo the deletion. Afterwards the app SHALL return to its first-launch state. The ALP contract is unchanged: connections close with the reason `account_deleted` and rejected tokens get `401 unauthorized`.

#### Scenario: Log out after two confirmations
- **WHEN** the user taps log out, confirms, and then confirms again on the second prompt, which reads "Logging out deletes all your Assistants, Assistant Links, and history. This can't be undone. Assistant Link permanently erases the data after 60 days."
- **THEN** the service marks the account deleted
- **AND** the app removes the stored credential and returns to the first-launch state with an empty Assistant list

#### Scenario: Cancel at either step
- **WHEN** the user taps log out and cancels at the first or the second confirmation
- **THEN** nothing is deleted and the app stays as it was

#### Scenario: Connected agents are disconnected
- **WHEN** the account is deleted while an agent is connected on one of its Links
- **THEN** that agent's connection is closed with the reason `account_deleted`
- **AND** its Link token is no longer accepted
- **AND** no `event.deliver` is started after the deletion

#### Scenario: Deleted credential no longer works
- **WHEN** a request arrives with a device credential, a Link token, or a pairing code of a deleted account
- **THEN** the credential and the Link token are rejected as unauthorized and the pairing code like an unknown code
- **AND** nothing of the account is returned, posted, or delivered, from the app or with `al send`

#### Scenario: Logging out an already deleted account
- **WHEN** the app logs out with the credential of an account that is already deleted
- **THEN** the service rejects it as unauthorized and the app treats it as logged out
- **AND** the account's `deleted_at` does not change

#### Scenario: Messages are unreachable, then erased
- **WHEN** the account is deleted after the user and the Assistant exchanged messages, some of them not yet delivered to an Assistant Link
- **THEN** no Assistant Link receives them and nobody can read them
- **AND** after the deletion grace period none of those messages remain in the service

#### Scenario: Purge after the grace period
- **WHEN** an account was deleted for longer than the deletion grace period
- **THEN** the service permanently deletes the account, everything it owns (Assistants, Assistant Links, pairing codes, Timeline events, message texts, cursors), and every user whose only account it was, with their devices

#### Scenario: Still within the grace period
- **WHEN** an account was deleted for less than the deletion grace period
- **THEN** the service does not purge it and keeps its data, which stays unreachable
