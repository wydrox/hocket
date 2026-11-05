# Hermes Pocket

A native SwiftUI iPhone and iPad client for an existing Hermes Agent gateway.
The phone presents conversations and controls; Hermes keeps model credentials,
tools, execution, and conversation authority on its server.

## Connect

Use an HTTPS Hermes gateway with the canonical `hermes-gateway-v1` session
authority. Sign in with its Basic provider username and password, or use the
advanced bearer-token option. Passwords are used only for sign-in; access and
refresh tokens are stored in the device Keychain. Private Tailscale addresses
require the device to be connected to the same tailnet.

## Native features

- Search, create, open, rename, and archive conversation threads.
- Stream replies, inspect tool activity, render Markdown and code, and stop a turn.
- Attach system-selected photos and documents; staging is disclosed before upload.
- Browse server commands and server-provided model, effort, and service-tier options.
- Answer approval, clarification, and secure-input requests.
- Reconnect using session snapshots and replay cursors; retain durable submission
  identifiers to avoid repeating a message after a lost acknowledgement.

Availability follows the connected Hermes server. The app does not replace its
server administration interface. Voice input uses the system keyboard's dictation.
Background push notifications and a phone-side agent runtime are not implemented.

## Project and cloud builds

- `project.yml` is the XcodeGen source; the generated project and shared scheme
  are checked in so Xcode Cloud needs no package installation.
- Target: iOS/iPadOS 27+, Swift 6, no third-party app dependencies.
- Bundle identifier: `com.wydrox.hermespocket`.
- `ci_scripts/` prepares and verifies Xcode Cloud inputs and build numbering.
- The manual **Validate iOS** GitHub workflow builds and runs unit tests in a
  hosted Xcode 27 environment. It does not sign or distribute an App Store build.

See [cloud setup and acceptance](docs/cloud-build.md),
[gateway contract](docs/hermes-api-contract.md),
[connection deployment](docs/mobile-connection-plan.md), and
[product spec and verification](docs/product/hermes-ios/README.md).

Build, device, and TestFlight status is recorded separately in
[release status](docs/release-status.md). Source completion alone is not a tested release.
