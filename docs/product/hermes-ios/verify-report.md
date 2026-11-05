# Verification record

Evidence updated 2026-11-05. Xcode Cloud build 2 passed all 34 tests, signed the app and distributed version 1.0.0 (2) to the internal TestFlight group. Live authenticated server flows, full-screen accessibility and physical-device acceptance remain separate unverified tiers.

| Evidence tier | Status | Required completion evidence |
|---|---|---|
| Product specification | Complete | Four linked artifacts, all principal screen states, capability boundaries and ethics decisions. |
| Contract alignment | Complete against installed canonical gateway source | Compare each feature and value source with the independent real-server contract report; update copy/scope for absent capabilities. |
| Static implementation review | Completed with attachment/model-confirmation fixes | SwiftUI/API review, Keychain and endpoint handling, privacy declarations, stable message identity and state transitions. |
| Native visual QA | Onboarding captures inspected on cloud iPhone Duo and iPhone 18 Pro; five final build-2 captures saved below. Remaining screens/iPad NOT_RUN | Actual screenshots at smallest supported iPhone, larger iPhone, regular iPad and narrow iPad window. |
| Accessibility | Onboarding light/dark, largest-text field/action traversal, HTTPS validation and access-token switch passed on iPhone 18 Pro. VoiceOver and other screens NOT_RUN | Accessibility Inspector, VoiceOver traversal, largest text, keyboard, light/dark/increased contrast/reduced motion. |
| Real server flows | NOT_RUN | Connection, actual threads/history, send/stream/reconcile, attachments, settings readback, commands and approvals as supported. |
| Xcode Cloud | PASS: build 2, Test + Archive + internal TestFlight post-action SUCCEEDED | Correct committed revision, workflow, successful signed archive and distribution logs. |
| TestFlight | PASS for distribution: build VALID, present in hocket Internal, owner INSTALLED. ASC reports iPad Pro 11-inch (M4), iOS 27.0; assistant-operated walkthrough NOT_RUN | App Store Connect processed build and intended tester availability; device install/open separately recorded if performed. |

## Build 2 evidence

- Source: `592f1d875edfaeb7f984a6234136a2ca6a5940a4`.
- [Xcode Cloud build](https://appstoreconnect.apple.com/teams/21e40dd1-5b96-4c70-a35e-f5b49ba22361/xcode-cloud/products/6df352ca-bec7-4a8a-b369-a2bb039dc3d9/builds/9e86f6b4-b959-4e27-a03d-4a0d4e610127/summary), completed 2026-11-05 10:55:39 UTC.
- 31 unit tests and 3 UI tests: all SUCCESS on iPhone 18 Pro, iOS 27.2.
- Native screenshots: [light](screenshots/iphone18pro-onboarding-light.png), [dark](screenshots/iphone18pro-onboarding-dark.png), [access token](screenshots/iphone18pro-onboarding-access-token.png), [largest-text address](screenshots/iphone18pro-onboarding-xxxl-address.png), [largest-text action](screenshots/iphone18pro-onboarding-xxxl-action.png).
- Known minor UX issue: after an invalid address is corrected, its prior inline validation error remains until the next connection attempt. It does not prevent a valid sign-in. This is visible in the access-token test capture.

## Native acceptance checklist

- [ ] Every screen's empty/loading/partial/error/success state is reachable with correct copy.
- [ ] No requested feature is faked or silently ignored; absent server capability is accurately explained.
- [ ] Connect validates endpoint/auth, preserves the previous configuration on failed edits and never logs a token.
- [ ] Offline/reconnect and uncertain delivery preserve draft and avoid duplicate submission.
- [ ] Stream interruption is distinct from completed/stopped output; cancellation status reflects actual acknowledgement.
- [ ] Attachments preview, validate, upload, fail and retry per item; source files remain untouched.
- [ ] Model/effort/tier values come from server; Save readback proves scope and effective settings.
- [ ] Command catalog/arguments/results are real; consequential actions receive appropriate context.
- [ ] Approval request details and both decisions remain visible and accessible; stale/expired/already-resolved requests reconcile safely.
- [ ] Compact-to-regular resizing retains selection, text, staged attachments and scroll context.
- [ ] Icon controls have labels and ≥44×44 pt targets; text expands without clipping.
- [ ] Text contrast is measured from actual rendered foreground/background values: ≥4.5:1 body and ≥3:1 large text/UI boundaries.
- [ ] VoiceOver does not announce every token; focus is logical and returns from sheets; keyboard can complete primary work.
- [ ] No content depends on color/motion alone; system appearance, contrast and motion settings work.
- [ ] Permission denials are recoverable and no unnecessary permission prompt appears at launch.
- [ ] Notifications/background claims match actual delivery capability, not an indefinite foreground socket assumption.
- [ ] Rerun ethical tests against built UI: transparency, symmetry, reversibility/clear irreversible disclosure, alignment.

## Scorecard and issue routing

Information / Meaning / Time / Memory: **not scored before a complete built walkthrough**. Ethics: **spec and static checks reviewed, live flows pending**. Accessibility: **partial onboarding evidence only**.

Route structure/copy issues to flow spec, wrong controls to component map, visual issues to visual direction, and behavior failures to implementation. All P0 completion, privacy, misleading-state or accessibility failures and P1 material friction must be resolved before claiming product acceptance. A successful build does not satisfy runtime or TestFlight acceptance.

Save actual native captures under `screenshots/` with screen/state/device/appearance in the filename. Do not use wireframes as screenshot evidence or web-browser checks as native accessibility evidence.
