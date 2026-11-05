# Verification

Independent static review found no blocking issues. `xcodegen generate --spec
project.yml`, `git diff --check` and `plutil -lint` on the project and Info.plist
passed. These are generation/structure checks, not compilation. No local build,
test suite or simulator run was performed.

Xcode Cloud build 3 (`e86e55e4-455b-4d0b-af46-4efc252cfe99`) ran from
`3683636b7cf2e051d8cbbdc558d8866b3acbc5bf` on 2026-11-05: **40 passed, 1 failed**.
The largest-text guide test inspected the presenting Form’s unchanged accessibility
tree while gestures scrolled the sheet. Its stationary-content detector then
reversed the scroll. Exported screenshot and hierarchy confirmed the diagnosis.
The helper now identifies and inspects the active guide Form and its navigation
bar. No assertion was removed. Distribution of build 3 was skipped; it is not in
the internal group.

The same run reported a deprecated URL-error key in the new unit test; it now uses
`NSURLErrorFailingURLErrorKey` with a URL value.

The existing private server was checked without credentials: provider discovery
returned HTTP 200 with `basic` / `supports_password:true`; protected sessions
returned HTTP 401. This verifies reachability and the password provider, not chat.

Coverage added: public provider response parsing (basic, Nous/other, unconfigured,
malformed/non-Hermes), actionable transport errors without URL leakage, complete
three-step navigation and return to entered address, largest Dynamic Type guide
continuation/dismissal, and clearing obsolete URL validation.

## Final cloud result

Build **4**, source `bd4a7c8700d69b92b11ca2210fc693ed1fe042ae`, completed
**SUCCEEDED** at 11:44:28 UTC on 2026-11-05. **41/41 passed** (36 unit, 5 UI),
iPhone 18 Pro / iOS 27.2. The test action reports no issues. Archive/signing and
the TestFlight post-action succeeded; Apple processed **1.0.1 (4)** as VALID and
IN_BETA_TESTING, and the build was read back in **hocket Internal**.

The corrected largest-text guide test now reaches Continue and closes the sheet.
The complete guide test opens the Desktop instructions, visits all three steps,
and verifies the entered address after returning. Existing tests retain
password/token entry, HTTPS enforcement, light/dark and largest Dynamic Type.

All ten exported PNGs were visually inspected and copied without modification
from the build 4 XCResult into [screenshots/](screenshots/). They cover preparation,
Desktop instructions, network setup, sign-in instructions, dark largest-text
guide, light/dark connection forms, token entry and largest-text address/action.
Text wraps and the tested controls remain reachable by scrolling. The native
compact toolbar places Previous Step in its More menu; Close stays visible.

No physical iPad or VoiceOver walkthrough was performed. Actual preflight network
error states are covered at the parser/error-message level, not captured in UI
screenshots. Real password sign-in and authenticated chat remain NOT_RUN; Nous
browser OAuth remains unsupported. Source-backed Hermes Desktop labels were not
verified against an installed Desktop bundle on this machine.

Assessment: Information / Meaning / Time / Memory improve through contextual
instructions, optional help and preserved address; no user-study measurement is
claimed. Ethics unchanged (public check only). Dynamic Type and appearance have
cloud UI/screenshot evidence; other accessibility modes remain unverified.
