# hocket

A native SwiftUI iPhone and iPad client for an existing Hermes Agent gateway.
The phone presents conversations and controls; Hermes keeps model credentials,
tools, execution, and conversation authority on its server.

## Connect

Use an HTTPS Hermes gateway with the canonical `hermes-gateway-v1` session
authority. Sign in with its Basic provider username and password, or use the
advanced bearer-token option. Passwords are used only for sign-in; access and
refresh tokens are stored in the device Keychain. Private Tailscale addresses
require the device to be connected to the same tailnet.

Tap **Set Up Hermes** on the connection screen for a three-step guide. It explains
the actual Desktop **Settings → Web access** controls, the separate password
provider requirement, Tailscale access, and which credentials to use. The same
guide is available in **Settings → Help and Privacy**. **Check Server** reads public
sign-in options without a password or chat request. Nous browser sign-in is not
supported in this beta; Web access alone does not enable hocket password login.

## Native features

- Search, create, open, rename, and archive conversation threads.
- Choose a Hermes profile from Threads or Settings; keep its saved connection
  preference and drafts separate from other profiles.
- Load older conversations in pages of 50, retaining loaded history on failures.
  Search covers the loaded conversations; load older pages to search more history.
- Stream replies, inspect tool activity, render Markdown and code, and stop a turn.
- Attach system-selected photos and documents; preview and share incoming images and files.
- Restore unsent drafts after app restarts, scoped to account and profile.
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
- Bundle identifier: `com.wydrox.hocket`.
- `ci_scripts/` prepares and verifies Xcode Cloud inputs and build numbering.
- **hocket · TestFlight** in Xcode Cloud tests, archives, signs and distributes
  successful builds to **hocket Internal**. It supports manual runs and changes
  on `main`; no signing credentials are needed in the repository.
- The manual **Validate iOS** GitHub workflow builds and runs unit tests in a
  hosted Xcode 27 environment. It does not sign or distribute an App Store build.

See [cloud setup and acceptance](docs/cloud-build.md),
[gateway contract](docs/hermes-api-contract.md),
[profiles and paginated history](docs/profiles-history.md),
[connection deployment](docs/mobile-connection-plan.md), and
[product spec and verification](docs/product/hermes-ios/README.md).

Build, device, and TestFlight status is recorded separately in
[release status](docs/release-status.md). Source completion alone is not a tested release.

The first internal beta is **1.0.0 (2)**, built and distributed by Xcode Cloud from
`592f1d875edfaeb7f984a6234136a2ca6a5940a4`. All 34 cloud tests passed.

The earlier onboarding beta was **1.0.1 (4)**, from
`bd4a7c8700d69b92b11ca2210fc693ed1fe042ae`. All **41 cloud tests passed**, and the
Xcode Cloud TestFlight action distributed it to **hocket Internal**. The update
adds guided connection setup and public server discovery; see the
[onboarding evidence](docs/product/connection-onboarding/verify-report.md).

The latest verified internal beta is **1.1.0 (7)**, from merged `main`
`a582b64a647766e54fd24c97baf71832ef61a0b7`. All **98 cloud tests passed**,
and the build is available in **hocket Internal**. It includes the new icon,
profile selection, paginated conversation history, read-only message history for
legacy threads, compact rows and the pinned connection footer; see
[release status](docs/release-status.md).

The source repository is public. No license file has been added.
