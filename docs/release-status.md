# Release status

Verified 2026-11-05. These are observed release states, not planned outcomes.

| Item | Observed state |
| --- | --- |
| Repository | Private [wydrox/hocket](https://github.com/wydrox/hocket), default branch `main` |
| App | `hocket: Hermes Agent`, Apple ID `6831068473`; device display name `hocket` |
| Bundle / team | `com.wydrox.hocket` / `7S3F9767BM` |
| Version | **1.0.1 (4)**, iOS/iPadOS 27+ |
| Released source | `bd4a7c8700d69b92b11ca2210fc693ed1fe042ae` |
| Xcode Cloud | Build 4 `8ebfecc2-435f-4ef2-bad4-6a76892d90b1`, **SUCCEEDED** at 11:44:28 UTC |
| Cloud tests | **41 passed**: 36 unit tests and 5 onboarding UI tests, iPhone 18 Pro / iOS 27.2 |
| Archive and signing | **SUCCEEDED** in Xcode Cloud, Xcode 27.2 (`27B52`) |
| Apple processing | **VALID**, internal-only build `146ddd66-1654-4d13-a5a6-b0a92c642ffd` |
| TestFlight distribution | Cloud post-action **SUCCEEDED**; build 4 read back in `hocket Internal`; beta state **IN_BETA_TESTING** |
| Tester | Requesting owner's account remains enrolled in the existing internal group |
| Device installation | Previously verified: 1.0.0 (2) on iPad Pro 11-inch (M4), iOS 27.0. Installation of 1.0.1 (4) is not yet verified. |
| Local checkout | `/Users/rafalw/Dev/hocket`, connected to `wydrox/hocket` |
| Local builds/tests | **NOT_RUN**; all compilation and test execution took place in the cloud |
| Assistant-operated device walkthrough / live authenticated chat / VoiceOver | **NOT_RUN** |

[Cloud build and results](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/xcode-cloud/products/6df352ca-bec7-4a8a-b369-a2bb039dc3d9/builds/8ebfecc2-435f-4ef2-bad4-6a76892d90b1/summary) · [TestFlight group](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/apps/6831068473/testflight/groups/88f6a4c3-af5f-46dc-acb3-9f0a83b71a6e).

## Onboarding update

Version 1.0.1 adds an optional three-step **Set Up Hermes** guide, also available
under **Settings → Help and Privacy**, and a credential-free **Check Server**
action. It explains the actual Desktop Web access controls, their Nous sign-in
limitation, private-network access and the required Hermes password credentials.
The guide preserves the entered address and supports the largest Dynamic Type.

Build 3 compiled and archived but failed one UI harness assertion (40/41 passed):
the test inspected the covered connection Form while trying to scroll the guide
sheet. Build 4 scopes gestures and visibility checks to the presented guide and
passes all 41 tests. Build 3 was **not** added to the internal group. The group
contains builds 2 and 4. See the [onboarding verification](product/connection-onboarding/verify-report.md)
and its ten unmodified cloud screenshots. No local compilation or simulator run
was used to validate this update.

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

Onboarding screenshots from the actual cloud test results are checked in with the
[first beta record](product/hermes-ios/verify-report.md) and the
[setup guide record](product/connection-onboarding/verify-report.md). TestFlight availability
does not establish a physical-device launch or authenticated end-to-end chat.
Voice entry uses system keyboard dictation. Background push notifications and a
phone-side Hermes runtime are outside this first beta.

Apple rejected bare `hocket` as already used; the accepted store name includes
the Hermes Agent subtitle while the installed app is named `hocket`.
