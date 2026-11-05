# Connection onboarding

Mode: **Improve**, 2026-11-05. Follow-up to the user’s request for instructions
showing where to click in Hermes and how to connect hocket.

| Stage | State |
| --- | --- |
| Preflight and source investigation | Done; installed Hermes SHA d49e2ebbaed42718659c13f82c04cde7d8ab10bd |
| UX specification | Done; [flow](flow-spec.md) |
| Gates A/B | User authorized autonomous completion and TestFlight delivery; no extra confirmation |
| Native component map | Done; [components](component-map.md); SwiftUI adaptation of master-product |
| Visual direction | Done; [direction](visual-direction.md); existing semantic styles preserved |
| Implementation | Done; source review and cloud validation pending |
| Verification | In progress; [record](verify-report.md) |

Applied master-product, apple-design and swiftui-pro. The web-only shadcn stage is
adapted to native components; no packages were installed. The improvement keeps
the established visual direction and makes setup help optional, as recommended by
Apple’s `onboarding.md` → Best practices. The inherited product brief records the
earlier psychology and component work; this bounded change applies progressive
disclosure, recognition over recall, and visible error recovery.

The guide does not change server settings or promise Nous authentication, QR
pairing, or a working canonical session merely because public discovery succeeds.
