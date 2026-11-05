# Verification

Source review and static project generation are in progress. No local build,
test suite or simulator run is performed; validation and screenshots are produced
by Xcode Cloud before this update is reported as available in TestFlight.

Coverage added: public provider response parsing (basic, Nous/other, unconfigured,
malformed/non-Hermes), actionable transport errors without URL leakage, complete
three-step navigation and return to entered address, largest Dynamic Type guide
continuation/dismissal, and clearing obsolete URL validation.

Existing tests retain password/token entry, HTTPS enforcement, light/dark and
largest Dynamic Type coverage. Real password sign-in, physical-device walkthrough,
VoiceOver and Nous OAuth remain NOT_RUN / unsupported as appropriate.

Provisional source assessment: Information / Meaning / Time / Memory improved by
contextual instructions, optional help and preserved address. Ethics unchanged
(public check only); accessibility requires cloud screenshot inspection.
