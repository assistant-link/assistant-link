Assistant Link — High-Level Product Spec

Product summary

Assistant Link is an iOS app and backend service that gives users a persistent mobile connection to their AI assistants.

It allows independently hosted AI agents to communicate with the user through voice, messages, notifications, and structured requests, and to request actions against resources available on the user’s iPhone.

The product is agent-runtime agnostic. An assistant may run locally, on a remote machine, or in the cloud.

ICP

Initial users:

* Early adopters running personal AI assistants.
* Users who want access to their assistant away from the computer where it runs.
* Users who want voice to be a primary interaction mode.
* Technical users willing to install/configure tooling on their agent environment.

Initial reference user: the product team itself.

Core concepts

Assistant
The user-facing identity of an AI assistant. Has a name, avatar, and history.

Assistant Link
A connection between an Assistant and a specific agent installation/runtime. An Assistant may have multiple Assistant Links—for example, a local Hermes instance and a cloud-hosted instance.

Assistant Link tooling
Software installed in the agent environment that authenticates with Assistant Link and exposes the communication and device-action APIs to the agent.

Timeline
The persistent interaction history between the user and an Assistant, including calls, messages, requests, actions, and relevant system events.

Core user experience

1. Assistant selection

The app opens to the user’s Assistants.

Each Assistant shows identity, connection status, and relevant recent activity.

Selecting an Assistant opens its timeline.

2. Assistant timeline

A chronological interface containing:

* Voice calls
* Incoming call requests
* Messages
* Device/resource requests
* Action requests and results
* Approvals/rejections
* Relevant connection events

The timeline is the primary asynchronous interaction surface.

3. Create and pair an Assistant

The user:

1. Creates an Assistant.
2. Sets its name and avatar.
3. Creates an Assistant Link.
4. Selects or describes the agent environment.
5. Assistant Link generates installation/pairing instructions intended to be given directly to the agent.
6. The agent installs/configures the required tooling and authenticates the Link.
7. The connection appears online in the app.

A user can create additional Assistant Links for the same Assistant later.

Primary capabilities

User-initiated voice

The user can call their Assistant from the app.

The app establishes a low-latency WebRTC session between the phone and the connected agent environment.

Assistant-initiated voice

The agent can call the user.

Assistant Link sends an incoming-call notification to the phone. The user can answer or decline. If answered, a WebRTC session is established.

Device resource access

Agents can request access to capabilities and resources exposed by the phone, where supported by iOS and installed integrations.

Examples include:

* Reminders
* Contacts
* Calendar
* Notes
* Files
* Photos
* Location
* Other application or device capabilities added over time

Access may include both reads and writes.

Example:

Agent requests: Create reminder “Call David tomorrow at 10 AM.”

Assistant Link presents the request to the user and, following the applicable permission/approval policy, executes it on the device.

Permission model

The user remains the authority over device access.

Permissions should support multiple scopes:

* Not available
* Ask each time
* Allowed for defined operations/resources

Sensitive actions can require explicit approval even when the underlying iOS permission has already been granted.

System model

At a high level:

Agent runtime ↔ Assistant Link service ↔ iOS app

The service provides:

* Authentication and pairing
* Connection routing
* Presence
* Push notifications
* Message/event delivery
* Request/response routing
* Session establishment

WebRTC provides the realtime media path for calls.

The agent connects outbound to Assistant Link infrastructure, avoiding the requirement for the user to configure VPNs, public IPs, port forwarding, or direct inbound access to the agent host.

Initial product boundary

The first version should focus on three jobs:

1. Reach my assistant from anywhere.
2. Let my assistant reach me.
3. Let my assistant securely ask my phone to do things.

Assistant Link does not define how the assistant thinks, which LLM it uses, or how its agent runtime operates. It provides the user/device connection layer between an existing assistant and its user.