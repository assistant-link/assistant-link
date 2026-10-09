# Security policy

## Reporting a vulnerability

Please do not report security vulnerabilities in public issues, discussions, or pull requests.

Report them privately through GitHub: open the **Security** tab of the affected repository and choose **Report a
vulnerability** (GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)).
It is enabled on every public Assistant Link repository:

- [assistant-link](https://github.com/assistant-link/assistant-link/security/advisories/new)
- [backend](https://github.com/assistant-link/backend/security/advisories/new): the service and the Assistant Link
  Protocol
- [cli](https://github.com/assistant-link/cli/security/advisories/new): `al`
- [apple](https://github.com/assistant-link/apple/security/advisories/new): the iOS app

If you are not sure which repository is affected, use assistant-link.

Include what you found, how to reproduce it, and what an attacker could do with it. We will acknowledge your report,
keep you updated while we work on a fix, and credit you in the published advisory unless you prefer otherwise.

## Scope

The code in these repositories, and the hosted service at `https://assistant-link.fly.dev`. When testing against the
hosted service, use only accounts and Assistants you created, and do not degrade the service for others. A
self-hosted service you run yourself is the best place to test.

## Supported versions

Fixes go into `main` of each repository and into the hosted service. There are no separate maintained release
branches yet.
