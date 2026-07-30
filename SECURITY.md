# Security Policy

## Supported Versions

Only the [latest release](https://github.com/hidrogenone/ClaudeNotch/releases/latest) is supported with security updates.

## Reporting a Vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/hidrogenone/ClaudeNotch/security/advisories/new) to report security issues — do not open a public issue for vulnerabilities.

You can expect an initial response within a few days. Please include steps to reproduce and the macOS/app version.

## Scope notes

ClaudeNotch makes exactly one kind of network request: HTTPS GET to the public Statuspage API at `status.claude.com`. It stores settings in `UserDefaults`, collects no analytics, and requires no special permissions or entitlements.
