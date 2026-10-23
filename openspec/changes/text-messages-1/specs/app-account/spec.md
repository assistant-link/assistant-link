## MODIFIED Requirements

### Requirement: Log out deletes the account
The user SHALL be able to log out from the app.
Because it cannot be undone, the app SHALL require two separate confirmations; the second SHALL state that all Assistants, Assistant Links, and history will be permanently deleted.
Logging out SHALL soft delete the account: the service SHALL record `deleted_at` and keep the data, and the account SHALL behave as deleted at once:

- Its device credentials and Link tokens are rejected as unauthorized, and its pairing codes like an unknown code.
- Web sessions and magic-link tokens of users whose only account it is stop working.
- Its data is not readable, postable, or deliverable.
- Its agent and app connections are closed with reason `account_deleted`.

Once `deleted_at` is older than the deletion grace period (a setting, default 60 days),
the service SHALL permanently delete the account, everything it owns, and users left with no membership, and no other account.
It SHALL delete rows explicitly, children first, not by a database cascade.
The user SHALL NOT be able to undo the deletion.
Afterwards the app SHALL return to its first-launch state.

#### Scenario: Log out after two confirmations
- **WHEN** the user taps log out and confirms twice
- **THEN** the service marks the account deleted
- **AND** the app removes the credential and returns to the first-launch state with an empty Assistant list

#### Scenario: Cancel at either step
- **WHEN** the user cancels at the first or second confirmation
- **THEN** nothing is deleted

#### Scenario: Connected agents are disconnected
- **WHEN** the account is deleted while an agent is connected
- **THEN** its connection closes with reason `account_deleted`

#### Scenario: Deleted credential no longer works
- **WHEN** a request arrives with a credential, Link token, or pairing code of a deleted account
- **THEN** nothing is returned, posted, or delivered

#### Scenario: Logging out an already deleted account
- **WHEN** the app logs out with the credential of an already deleted account
- **THEN** the service rejects it as unauthorized, the app treats it as logged out, and `deleted_at` does not change

#### Scenario: Purge after the grace period
- **WHEN** an account was deleted longer than the grace period
- **THEN** the service deletes it, everything it owns, and its users with no membership left, with or without an email
- **AND** no other account is touched, and a user still in another account is kept
