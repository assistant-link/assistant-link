# app-account Specification

## Purpose

Gives each iOS app install an identity with the Assistant Link service, so that the user's Assistants and Assistant Links belong to them and only they can see and manage them, and lets the user remove that identity and all its data.

## Requirements

### Requirement: Anonymous account on first launch
The iOS app SHALL register an account with the service the first time it launches, without asking the user to sign in. The app SHALL store the account credential securely on the device and reuse it on later launches.

#### Scenario: First launch registers an account
- **WHEN** the app launches and has no stored account credential
- **THEN** the app registers a new account with the service
- **AND** the app stores the returned credential on the device
- **AND** the user sees their (empty) list of Assistants without any sign-in step

#### Scenario: Later launches reuse the account
- **WHEN** the app launches and a stored account credential exists
- **THEN** the app uses that credential and does not register a new account
- **AND** the user sees the Assistants they created earlier

### Requirement: Account-scoped access
The service SHALL require the account credential on every app request, and SHALL only return or modify Assistants and Assistant Links that belong to the authenticated account.

#### Scenario: Request without a credential is rejected
- **WHEN** an app request arrives without a valid account credential
- **THEN** the service rejects it as unauthorized and returns no account data

#### Scenario: Another account's data is not visible
- **WHEN** account A requests an Assistant that belongs to account B
- **THEN** the service responds as if the Assistant does not exist

### Requirement: Log out deletes the account
The user SHALL be able to log out from the app. Because logging out cannot be undone, the app SHALL require two separate confirmations; the second SHALL state that all Assistants, Assistant Links, and history will be permanently deleted. On confirmation the service SHALL permanently delete the account and everything it owns (Assistants, Assistant Links, Link tokens, pairing codes, and history), and SHALL disconnect any agents connected on those Links. Afterwards the app SHALL return to its first-launch state.

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
