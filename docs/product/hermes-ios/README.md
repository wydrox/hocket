# hocket — native product brief

Mode: **Build**. Target: a native SwiftUI iPhone/iPad client for the user's Hermes agent, replacing the Telegram interaction surface. Display name: **hocket**; bundle ID: `com.wydrox.hocket`. Date: 2026-11-05.

The product thesis is a quiet messenger that keeps the conversation central and makes the agent's actual work, connection, and permission requests easy to understand.

## Stage log

| Stage | Status | Evidence / next action |
|---|---|---|
| 0 — Preflight | done | New native project; supplied brief is the source of scope. No existing UI or screenshots were supplied. |
| 1 — UX specification | done | [flow-spec.md](flow-spec.md); server-dependent behavior is explicitly conditional. |
| Gate A — flow approval | done | Caller reports explicit user preapproval of autonomous product decisions; no additional approval requested. |
| 2 — native component map | done, adapted | [component-map.md](component-map.md); SwiftUI/system components replace the web-specific shadcn stage. |
| 3 — visual direction | done | [visual-direction.md](visual-direction.md); semantic palette and system text styles. |
| Gate B — visual approval | done | Same explicit user preapproval; the ASCII layouts record the concrete decision. |
| 4 — implementation | done, validation pending | Native source in `Sources/`, protocol tests in `Tests/`. Independent source review issues corrected. |
| 5 — runtime and visual verification | in progress | Cloud tests and onboarding screenshot suite; [verify-report.md](verify-report.md) tracks evidence. Authenticated chat/device acceptance is pending. |
| Xcode Cloud build / TestFlight | blocked | Apple account onboarding required; [release status](../../release-status.md) records the exact state. |

## Scope and priority

P0: secure real-server setup, thread navigation, actual history, send/stream/cancel where supported, attachment preparation and supported upload, server-provided model/effort/service-tier controls, discoverable commands, recoverable connection and send errors, visible actionable approvals where supported, Dynamic Type and VoiceOver.

P1: local thread/history search, attachment previews/export, iPad keyboard and pointer, drag and drop, local draft restoration, app lock, contextual camera and document capture, speech input when a real transcription path exists, useful notification support when delivery is real.

P2: Share extension, App Intents/Shortcuts, Spotlight, widgets, Live Activities, multiple windows, deeper media tools. Evaluate against the same real contract and privacy boundary; a disabled or decorative control does not satisfy the feature.

All advertised controls must work against an observed server contract. If a requested capability is absent, expose a clear limitation in Help and report it as pending; do not simulate a response, silently ignore an option, or claim Telegram replacement is complete. The contract investigation runs independently and owns endpoint truth. These documents intentionally do not invent API paths.

## Applied skills and adaptations

Read `master-product` (Build stages), `apple-design`, `uxled-psychology` (Design mode), and `frontend-design`. The parent owns the `swiftui-pro` implementation review.

The shadcn skill and `design:*` plugin are unavailable. Their documented generic installation commands are `pnpm dlx skills add shadcn/ui` and `claude plugin marketplace add anthropics/knowledge-work-plugins` followed by `claude plugin install design@knowledge-work-plugins`. Neither is installed: the first is a web component stack, while native accessibility is verified with Accessibility Inspector and VoiceOver. The master-product verification checklist is adapted to native screens. No browser app or web styling dependency is introduced.

## Reference ledger

Apple files were read from `/Users/rafalw/.agents/skills/apple-design/references/hig/`. Quotes below identify the relevant source guidance; implementation still requires runtime checks.

| Read reference and heading | Short source wording | Consequence |
|---|---|---|
| `accessibility.md` › Vision / Mobility | “Convey information with more than color alone.” | Labels, symbols, 44 pt targets, VoiceOver. |
| `layout.md` › Adaptability | “Determine layout based on size classes” | Preserve functions as windows resize; collapse columns. |
| `typography.md` › Supporting Dynamic Type | “Make sure your app’s layout adapts to all font sizes.” | Semantic styles, variable row heights, stacked controls. |
| `color.md` › System colors | “Avoid hard-coding system color values in your app.” | Semantic colors; appearance and contrast variants. |
| `designing-for-ios.md` › Best practices | “Support interactions that accommodate the way people usually hold their device.” | Bottom composer and native back navigation. |
| `split-views.md` › Tablet (iPadOS) | “Account for narrow, compact, and intermediate window widths.” | Threads/detail adapt without losing selection. |
| `entering-data.md` › Best practices | “Dynamically validate field values.” | Inline URL validation and attachment constraints. |
| `loading.md` › Showing progress | “Clearly communicate that content is loading” | Actual loading state; no fictional stage progress. |
| `generative-ai.md` › Best practices | “Keep people in control.” | Visible approval decisions, stop, retry, AI attribution. |
| `privacy.md` › Protecting data | “Store sensitive information in a keychain.” | Keychain token; no secrets in defaults/logs. |
| `settings.md` › Task-specific options | “modify task-specific options without going to your settings area” | Model, effort and tier stay in the conversation. |
| `notifications.md` › Best practices | “Avoid including sensitive, personal, or confidential information in a notification.” | Generic previews and no approval action without context. |

Psychology references read: `references/playbooks.md` (§1–5), `references/audit-and-ethics.md` (four lenses and four ethical tests), relevant canonical entries in `references/principles.md`, and `templates/flow-spec.md`. Master-product's `references/verify.md` was read for native adaptation. No claim is made that design scores constitute a tested user study.

## Current scorecard

Information / Meaning / Time / Memory: **not yet scored on built UI**. Ethics: **specification passes**, runtime recheck pending. Accessibility: **specified, not verified**. Screenshots, device operation, Cloud build, App Store processing and TestFlight installation: **NOT_RUN by this design task**.
