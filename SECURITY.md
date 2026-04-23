# Security Policy

## Scope

This project is a local SSH onboarding helper.

Its intended security posture is:

- server passwords are typed by the end user into `ssh` / `ssh-copy-id`
- passwords are never written into local config files
- private keys stay on the local machine

## Reporting

If you discover a security issue, do not publish sensitive details in a public issue first.

Recommended path:

1. prepare a minimal reproduction
2. list affected files and exact impact
3. share only the minimum needed details with the maintainer

## Safe usage notes

- Always verify the generated SSH alias and key path before distributing the tool.
- Do not bundle real private keys or real passwords in test fixtures.
- Do not automate deletion of old keys unless the user explicitly confirms the recovery path.
