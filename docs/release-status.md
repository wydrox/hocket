# Release status

Verified 2026-11-05. These are observed release states, not planned outcomes.

| Item | Observed state |
| --- | --- |
| Repository | Private [wydrox/hocket](https://github.com/wydrox/hocket), default branch `main` |
| App | `hocket: Hermes Agent`, Apple ID `6831068473`; device display name `hocket` |
| Bundle / team | `com.wydrox.hocket` / `7S3F9767BM` |
| Version | **1.0.0 (2)**, iOS/iPadOS 27+ |
| Released source | `592f1d875edfaeb7f984a6234136a2ca6a5940a4` |
| Xcode Cloud | Build 2 `9e86f6b4-b959-4e27-a03d-4a0d4e610127`, **SUCCEEDED** at 10:55:39 UTC |
| Cloud tests | **34 passed**: 31 unit tests and 3 onboarding UI tests, iPhone 18 Pro / iOS 27.2 |
| Archive and signing | **SUCCEEDED** in Xcode Cloud, Xcode 27.2 (`27B52`) |
| Apple processing | **VALID**, internal-only build `ffcb86f8-6a0a-40c0-bdc5-63620097147d` |
| TestFlight distribution | Cloud post-action **SUCCEEDED**; build 2 read back in `hocket Internal` |
| Tester | Requesting owner's account enrolled; current state **INSTALLED** |
| Device installation | App Store Connect reports 1.0.0 (2) installed on iPad Pro 11-inch (M4), iOS 27.0 |
| Local builds/tests | **NOT_RUN**; all compilation and test execution took place in the cloud |
| Assistant-operated device walkthrough / live authenticated chat / VoiceOver | **NOT_RUN** |

[Cloud build and results](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/xcode-cloud/products/6df352ca-bec7-4a8a-b369-a2bb039dc3d9/builds/9e86f6b4-b959-4e27-a03d-4a0d4e610127/summary) · [TestFlight group](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/apps/6831068473/testflight/groups/88f6a4c3-af5f-46dc-acb3-9f0a83b71a6e).

## Pipeline

The connected product is `6df352ca-bec7-4a8a-b369-a2bb039dc3d9`; the workflow
**hocket · TestFlight** is `662108ED-715A-440E-B46A-8501DC219743`.
It requires the Test and Archive actions to pass before the internal TestFlight
post-action distributes to group `88f6a4c3-af5f-46dc-acb3-9f0a83b71a6e`.
Manual runs and changes on `main` are supported. Pull-request and scheduled
triggers are disabled. Changes confined to `docs/` and `README.md` skip automatic
builds; a change to application code still starts a build when documentation also
changes. Build numbers come from Xcode Cloud.

The first default build used the old initial commit and was canceled. GitHub
simulator runs diagnosed and corrected the onboarding test harness. The final
release was tested, signed and distributed entirely by Xcode Cloud; earlier
failed GitHub runs are not represented as passing.

An unused GitHub signing fallback was prepared during repository authorization
and never executed. It has been removed. Its three Actions secrets were deleted,
the dedicated `hocket-release` API key `23AZWY8946` was revoked, and its local
private-key file was removed. Existing API keys and signing certificates were
preserved. Xcode Cloud uses Apple's managed signing.

## Connection and acceptance boundary

The existing tailnet-only HTTPS route at
`https://rafals-mac-mini.tail71fdd0.ts.net:8443` points to the canonical Hermes
gateway on loopback port 55263. Provider discovery returned HTTP 200; protected
sessions returned 401 without credentials. The separate root HTTPS route was
preserved. No gateway restart or conversation mutation was performed.

The iPhone needs Tailscale connected to the same tailnet and the owner's Hermes
login. The gateway's loopback port is ephemeral: the Serve route needs resync
after a gateway restart. See [connection deployment](mobile-connection-plan.md).
No real Hermes password or token was retrieved or embedded in the app.

Onboarding screenshots from the actual cloud test result are checked in with the
[verification record](product/hermes-ios/verify-report.md). TestFlight availability
does not establish a physical-device launch or authenticated end-to-end chat.
Voice entry uses system keyboard dictation. Background push notifications and a
phone-side Hermes runtime are outside this first beta.

Apple rejected bare `hocket` as already used; the accepted store name includes
the Hermes Agent subtitle while the installed app is named `hocket`.
