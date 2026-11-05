# hocket cloud build

The repository contains the generated `HermesPocket.xcodeproj`, the shared `HermesPocket` scheme, and the XcodeGen source specification in `project.yml`. Xcode Cloud builds the checked-in project directly; it does not install XcodeGen or any package dependency. Regenerate the project with `xcodegen generate` after adding source files or changing the specification, then commit both.

## Product settings

| Setting | Value |
| --- | --- |
| App | hocket |
| Bundle ID | `com.wydrox.hocket` |
| Team | `7S3F9767BM` |
| Deployment | iOS 27.0, iPhone and iPad |
| Cloud toolchain | Xcode 27.2 (`27B52`), verified available November 5, 2026 |
| Language | Swift 6, complete strict concurrency |
| Marketing version | `1.0.0` |
| Signing | Automatically managed by Xcode Cloud |

## Workflow configuration

Onboard the product and its first workflow in **Xcode**, named **hocket · TestFlight**. After onboarding, manage workflows in App Store Connect, Xcode, or the supported API. Workflow configuration lives in Apple's service; a local scheme alone does not create it.

1. Connect this repository and select `HermesPocket.xcodeproj`, shared scheme `HermesPocket`, and Xcode 27.2. Use the macOS version compatible with that toolchain.
2. Start manually for the first build on the committed product branch. Keep pull-request and scheduled triggers off initially to avoid unrelated build usage.
3. Add **Test**: iOS simulator, one available iPhone running iOS 27 or later, Debug configuration, `HermesPocketTests`, with one device and no repetitions.
4. Add **Archive**: iOS, Release configuration, automatic signing, deployment preparation **TestFlight (Internal Testing Only)**. Require successful Test before distributing.
5. Create an internal TestFlight tester group if needed, then add the **TestFlight Internal Testing** post-action for that group. Do not enable external beta review or App Store submission.
6. Confirm the App Store Connect app record uses the exact bundle ID and team above. Start the workflow for the intended commit and record the build URL and commit SHA.

Apple documents the archive and internal distribution settings in [Creating a workflow that builds your app for distribution](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution) and [Distributing your Xcode Cloud builds through TestFlight](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight).

## Build scripts

Both scripts are executable and live beside the project in `ci_scripts`, following [Apple's custom script conventions](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).

- `ci_post_clone.sh` validates required inputs and property lists and prints the selected toolchain. It does not fetch dependencies or inspect credentials.
- `ci_pre_xcodebuild.sh` sets `CURRENT_PROJECT_VERSION` in `Config/Version.xcconfig` from Apple's [predefined `CI_BUILD_NUMBER`](https://developer.apple.com/documentation/xcode/environment-variable-reference). It skips `test-without-building`, which reuses the already compiled test binary. The app Info.plist expands that setting into `CFBundleVersion`.

No workflow secrets are needed. Users enter their own Hermes server address and credentials in the app. ATS remains at its secure defaults. `ITSAppUsesNonExemptEncryption` is false for the app's system TLS use.

## Acceptance evidence

A generated project and passing property-list checks demonstrate configuration only. Keep these results separate:

- Cloud Test result and exact commit SHA.
- Cloud Archive and signing result.
- App Store Connect processing result and version/build number.
- Internal group distribution and TestFlight availability.
- Real-device launch and interaction results, when performed.

No local compilation or simulator test is required by this workflow. Do not describe pending, failed, or unrun cloud actions as passing, or a successfully uploaded archive as a verified device run. The manual GitHub Actions fallback below validates the committed app while initial Xcode Cloud onboarding is unavailable.


## Initial onboarding and API feasibility

Verified November 5, 2026, using read-only requests and Apple's official [OpenAPI specification](https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip), version 4.6:

| Public endpoint | Supported collection methods |
| --- | --- |
| `/v1/apps` | GET |
| `/v1/ciProducts` | GET |
| `/v1/ciWorkflows` | POST |
| `/v1/ciBuildRuns` | POST |

There is no supported public create-product or create-app-record endpoint in that specification. The initial authenticated product listing returned one existing product, OpenPing Mobile, with no next page; hocket required separate onboarding. An existing team's Cloud product does not onboard this new product automatically.

Apple explicitly requires initial configuration in Xcode in [Configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow) and the [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference). Open this project in Xcode, use Report navigator → Cloud → Get Started (or Integrate → Create Workflow), select hocket and its team, and grant the new repository access. The assistant can create a matching app record when the account has permission. Repository authorization can open a browser and require an App Store Connect sign-in. An API key alone cannot complete this initial UI onboarding.

After the product exists, use the public API to create/update workflows, start builds, and read status. Do not repurpose an unrelated existing product or repository as an onboarding workaround.


## Manual GitHub Actions fallback

`.github/workflows/validate.yml` runs only on manual dispatch. It uses the [GA standard `xcode-27` runner](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/), one test job, a 20-minute timeout, and one available iPhone simulator with iOS 27 or later. The job selects the newest installed stable Xcode 27.x and fails clearly if the toolchain or simulator is missing; it never installs a toolchain. The older `macos-26` image is not an appropriate Xcode 27 fallback.

The job uses ad-hoc simulator signing so Keychain entitlements work, runs the shared scheme's unit and onboarding UI tests, and exports screenshots, the simulator app, `.xcresult`, and logs with seven-day retention. It uses no signing credentials, larger runners, or third-party hosted services. Dispatch it for the exact pushed branch and record its commit SHA and result. This workflow validates build/tests only. Xcode Cloud remains the intended signed archive and TestFlight pipeline.
