# Release status

Verified 2026-11-06. These are observed release states, not planned outcomes.

| Item | Observed state |
| --- | --- |
| Repository | Public [wydrox/hocket](https://github.com/wydrox/hocket), default branch `main`; anonymous GitHub API read returned HTTP 200 |
| App | `hocket: Hermes Agent`, Apple ID `6831068473`; device display name `hocket` |
| Bundle / team | `com.wydrox.hocket` / `7S3F9767BM` |
| Version | **1.1.0 (7)**, iOS/iPadOS 27+ |
| Released source | `a582b64a647766e54fd24c97baf71832ef61a0b7`, merged `main` |
| Xcode Cloud | Automatic build 7 `74b865ed-876f-44b8-be7d-3736df3a9eb8`, **SUCCEEDED** at 22:14:03 UTC |
| Cloud tests | **98 passed**: 93 unit tests and 5 onboarding UI tests, iPhone 18 Pro / iOS 27.2 |
| Archive and signing | **SUCCEEDED** in Xcode Cloud |
| Apple processing | **VALID**, internal-only build `22daca54-3ebf-4880-bc3f-6c50538dc970` |
| TestFlight distribution | Cloud post-action **SUCCEEDED**; build 7 read back in `hocket Internal`, state **IN_BETA_TESTING**, at 22:14:30 UTC |
| Tester | Existing internal group preserved; installation of build 7 has not been verified |
| Device installation | **NOT_RUN for build 7** |
| Local checkout | `/Users/rafalw/Dev/hocket`, connected to `wydrox/hocket` |
| Local builds/tests | **NOT_RUN**; all compilation and test execution took place in the cloud |
| Assistant-operated device walkthrough / live authenticated chat / VoiceOver | **NOT_RUN** |

[Cloud build and results](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/xcode-cloud/products/6df352ca-bec7-4a8a-b369-a2bb039dc3d9/builds/74b865ed-876f-44b8-be7d-3736df3a9eb8/summary) · [TestFlight group](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/apps/6831068473/testflight/groups/88f6a4c3-af5f-46dc-acb3-9f0a83b71a6e).

Build 7 is the first public-main 1.1.0 beta. It includes the new icon, Hermes
profile selection and isolated drafts, paginated conversation history, compact
thread rows and the pinned connection footer. Stored legacy conversations that
Hermes cannot resume remotely now display authenticated, profile-scoped read-only
message history with earlier-page loading. Failed opens expose Retry instead of
the generic empty placeholder. Canonical conversations retain their controls.

PR #1 was merged before the automatic cloud run. The 9e37363 Swift/test sources
passed 93 unit and 5 UI tests in GitHub CI on attempt 2; the initial run had a UI
snapshot-query timeout. The merged main revision adds the version, icon and docs,
and independently passed all 98 tests in Xcode Cloud. Archive/signing, Apple
processing, internal group membership and beta notes were read back separately.
Physical installation and authenticated live Hermes acceptance remain unverified;
the requested native simulator screenshot review remains deferred by the user.

The repository is public. No license file has been added. Public-branch history
was scanned by Gitleaks with no secret findings; local operational evidence and
Drawspeak feedback artifacts were not committed. Current docs use example host
names; older commits can still contain non-secret operational host identifiers.

## Onboarding update

Version 1.0.1 adds an optional three-step **Set Up Hermes** guide, also available
under **Settings → Help and Privacy**, and a credential-free **Check Server**
action. It explains the actual Desktop Web access controls, their Nous sign-in
limitation, private-network access and the required Hermes password credentials.
The guide preserves the entered address and supports the largest Dynamic Type.

Build 3 compiled and archived but failed one UI harness assertion (40/41 passed):
the test inspected the covered connection Form while trying to scroll the guide
sheet. Build 4 scopes gestures and visibility checks to the presented guide and
passes all 41 tests. Build 3 was **not** added to the internal group. At that point the group
contained builds 2 and 4; builds 5, 6 and 7 were subsequently added. See the [onboarding verification](product/connection-onboarding/verify-report.md)
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

The owner’s private tailnet-only HTTPS route on port 8443 points to the canonical Hermes
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
