# hocket cloud build

The checked-in `HermesPocket.xcodeproj` and shared `HermesPocket` scheme build
without installing project generators or package dependencies. `project.yml`
is the XcodeGen source; regenerate and commit the project after changing it.

## Active configuration

| Setting | Value |
| --- | --- |
| Workflow | **hocket · TestFlight** |
| Product / workflow ID | `6df352ca-bec7-4a8a-b369-a2bb039dc3d9` / `662108ED-715A-440E-B46A-8501DC219743` |
| Repository | `wydrox/hocket`, `HermesPocket.xcodeproj`, scheme `HermesPocket` |
| Bundle / team | `com.wydrox.hocket` / `7S3F9767BM` |
| Deployment | iOS/iPadOS 27+, iPhone and iPad |
| Language | Swift 6, complete strict concurrency |
| Toolchain | Latest release; currently Xcode 27.2 (`27B52`), macOS 27.2 (`26B123`) |
| Start conditions | Manual branch runs and changes on `main`; no schedules or pull-request triggers |
| Test | Required to pass, shared scheme, one iPhone 18 Pro with selected Xcode's iOS runtime |
| Archive | Required to pass, iOS, internal-only TestFlight preparation |
| Post-action | TestFlight Internal Testing, Archive - iOS, group **hocket Internal** |
| Signing | Managed by Xcode Cloud; no repository signing secrets |

[Workflow in App Store Connect](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/xcode-cloud/products/6df352ca-bec7-4a8a-b369-a2bb039dc3d9/workflows/662108ED-715A-440E-B46A-8501DC219743).
The first full run, build 2, tested, signed and distributed version 1.0.0 (2).
The latest verified beta, **1.0.1 (5)**, was manually built from
`4798d93b516db2c0ba1e02e931027fe4d73674bb` on `fix/review4-thread-list-chat`.
All 56 tests, Archive, and the internal TestFlight post-action passed; Apple
processing is VALID and the build is IN_BETA_TESTING in `hocket Internal`.
See the exact revision, distribution readback and acceptance limits in
[release status](release-status.md).

## Build scripts

The executable scripts live beside the project in `ci_scripts`, following
[Apple's custom-script conventions](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).

- `ci_post_clone.sh` verifies project inputs and property lists and prints the toolchain. It does not fetch dependencies or inspect credentials.
- `ci_pre_xcodebuild.sh` writes `CURRENT_PROJECT_VERSION` from Apple's predefined `CI_BUILD_NUMBER` into `Config/Version.xcconfig`. It skips `test-without-building`, which reuses compiled test products.

Users enter their Hermes endpoint and credentials on the device. No backend
credential is required for the cloud build. ATS retains secure defaults;
`ITSAppUsesNonExemptEncryption` is false for system TLS use.

## Subsequent builds

Push an intended release revision to `main`, or start this workflow manually in
App Store Connect. Xcode Cloud increments its build number, runs the required
tests, archives with automatic signing, and distributes to the internal group.
Automatic builds skip commits that change only `docs/` and `README.md`.
Do not equate an uploaded archive with a completed release: verify successful
actions, Apple processing, group membership and tester availability separately.
Device installation and live-server testing remain separate evidence tiers.

Apple documents [distribution workflows](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)
and [TestFlight post-actions](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight).

## Supplemental simulator validation

The manual `.github/workflows/validate.yml` uses the standard `xcode-27` runner,
one available iPhone with iOS 27+, ad-hoc simulator signing, and a 20-minute timeout.
It runs unit and onboarding UI tests and exports screenshots, the simulator app,
logs and `.xcresult` with seven-day retention. It does not sign or distribute a
TestFlight archive. No larger runner or downloaded toolchain is used.

## Onboarding and retired fallback

The product was initially configured in native Xcode. GitHub repository access
was completed in the authorized Helium Rafał profile. Workflow configuration
lives in Apple's service; the project manifest alone does not create it.

An API-only bootstrap was unavailable: Apple's public OpenAPI 4.6 exposes GET
for the `/v1/apps` and `/v1/ciProducts` collections, while workflows and build runs
can be created after onboarding. Existing unrelated products were preserved.

During browser authorization, a separate GitHub signing fallback was prepared
but never executed. Once Xcode Cloud succeeded, its workflow and three repository
secrets were removed, the dedicated Admin API key `hocket-release` was revoked,
and its downloaded private key was deleted. No signing certificates or existing
API keys were revoked. Xcode Cloud needs none of that fallback material.
