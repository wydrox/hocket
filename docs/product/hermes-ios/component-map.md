# Native component map

This adapts master-product Stage 2 to SwiftUI. System components own platform behavior; small compositions own Hermes-specific meaning. No shadcn, webview, custom navigation chrome, dependency installation, or source implementation is part of this artifact.

| Spec element | Native component / composition | Behavior and acceptance |
|---|---|---|
| Threads → Chat | Two-column `NavigationSplitView`, `List(selection:)`, navigation destination | Native collapse/back; selected ID and per-thread draft survive resizing. Persistently highlight selection in regular width. |
| Thread row | `Label`/`Text` stack plus date/state | Body/headline and secondary metadata; variable height; full-row target. Keep meaningful text at accessibility sizes. |
| New Thread / Settings | `ToolbarItem`, `Button`, `Label` | SF Symbols `square.and.pencil`, `gearshape`; voice labels **New Thread**, **Settings**. Each target ≥44×44 pt. |
| Search | `.searchable`, native search field | Accurate scope label; cancellation restores list and selection; large collections do not require command recall. |
| Connection form | `Form`, `Section`, `TextField`, `SecureField` | Persistent labels; URL keyboard, no autocapitalization/autocorrection; secure token entry; validation and first-error focus. |
| Token persistence | Security Keychain service behind an isolated store | Device-only policy appropriate to app; no token in UserDefaults, logs, previews or screenshots. Endpoint can be nonsecret settings. |
| Connection/activity signature | `Label` composition with tiny route mark and real state text | **Connected**, **Connecting…**, **Offline**, **Responding**, **Approval Required**. Connection and agent work are distinct data, not inferred from each other. |
| Transcript | `ScrollView` + lazy stack with stable message identity | Reading order, selectable content, preserved scroll position; bottom-follow only when appropriate. Profile before custom virtualization. |
| Assistant message | Native `Text`/`AttributedString` for supported Markdown plus code/attachment subviews | Select/copy; safe links; local horizontal code scrolling; explicit **Hermes · AI** role; no executable markup. |
| User message | `Text` in a semantic secondary-background bubble | Trailing alignment, max readable width; accessible “You, {text}, {delivery state}”. Delivery uncertainty remains visible. |
| Composer | Multiline `TextField(axis: .vertical)` or native `TextEditor`, `FocusState` | Min 1 line, expands to roughly 5 lines before internal scrolling; actual input always visible; semantic font; no fixed height at large text. |
| Bottom composer placement | `.safeAreaInset(edge: .bottom)` | Respects keyboard/safe areas. No absolute screen coordinates or device-model branching. |
| Send / Stop | Native `Button` and `Label` | One current primary action. Disable send for empty/unready data and duplicate pending send; stop only if real API supports it. Keyboard Command-Return sends. |
| Add Attachment | `Menu` with `Label` actions | Photos, Files, camera, scan, audio only when corresponding implementation works. **Add Attachment** is the accessibility label. |
| Photos | `PhotosPicker` | Access chosen items through system selection; no full-library permission for simple selection. Validate and stage locally. |
| Files | `.fileImporter` / document picker | Copy/import securely from scoped URLs; release scoped access; no source-file destruction. |
| Camera / scan | System camera and VisionKit scanner through minimal UIKit bridges | Present only on supported devices; denied/unavailable paths offer Files. Usage descriptions match real behavior. |
| Audio | AVFoundation recording composition, if real upload path exists | Visible start/stop/elapsed state; explicit microphone request; review/remove before send. Do not expose a decorative microphone. |
| Attachment row | Thumbnail/type `Label`, metadata, `ProgressView`, Remove button | Independent pending/error/ready state, server limits and type; Remove target ≥44 pt. |
| Preview / export | Quick Look bridge, system activity/share sheet or `ShareLink` | Actual local/downloaded content; controlled fetch; system dismissal; no fake file success. |
| Session Options | `sheet` with `NavigationStack`, `Form`, `Picker`, Cancel/Save toolbar | Native medium/large detents where useful, one sheet at a time; server catalog, pending versus effective state. |
| Commands | Searchable `List`; selected command `Form` | Native list navigation; arguments retain values after failure; Run reaches real server. |
| Tool details | `DisclosureGroup` | Concise factual summary first, actual details second. Unknown tool activity is labelled generically rather than invented. |
| Approval request | Inline grouped section with details and two native buttons | Both decisions accessible; no preselected approval; unavailable details cannot approve blindly; server-confirmed result persists. |
| Recoverable error | Inline `Label` + cause/action `Button` | No alert storm; distinguish stale content from empty; retry keeps draft. Accessibility announcement only at useful transitions. |
| Irreversible action | `confirmationDialog` or `alert` with Cancel | Actual consequence described. Prefer Undo for truly reversible archive/edit actions; never promise undo without capability. |
| App Lock | LocalAuthentication behind optional privacy setting | Use device authentication policy and accessible fallback; never store biometrics. Lock state must also protect app-switcher snapshots if promised. |
| Notifications | UserNotifications registration only after real push/local-delivery design exists | Generic content; no duplicates; open correct thread. No claim of background stream continuity. |
| Keyboard / pointer | `.keyboardShortcut`, native focus/hover behavior, `.onDrop`/`dropDestination` | Command-N new thread, Command-F search, Command-Return send; verify conflict-free behavior and drag validation on iPad. |

## Shared view states

Compose separate `loading`, `empty`, `error`, `content` and `staleContent` states; a single `isLoading` boolean cannot express cached data plus refresh failure. The transport model owns actual send/delivery/run/approval state. The view must not convert an ended network task into agent completion.

Bespoke components are justified only for transcript message presentation, staged-attachment rows, approval details and the connection/activity signature: these encode Hermes-specific state that a plain system list row cannot convey by itself. Keep navigation, forms, pickers, dialogs, loading indicators and permission experiences native.

## Accessibility contract

All icon actions have visible labels in menus and descriptive accessibility labels in toolbars. Use semantic fonts and foreground styles; no fixed message-row heights, truncation of critical errors, tiny captions for actionable states, or color-only distinctions. Focus returns to the originating control when a sheet closes; validation focuses the failing field. Reduce Motion removes repeated activity animation, Reduce Transparency supplies clear surfaces, and Bold Text/Increase Contrast remain system-driven. VoiceOver reads complete messages without announcing every streaming token.

Reference basis: `split-views.md` › Best practices / Tablet; `layout.md` › Adaptability / Guides and safe areas; `typography.md` › Supporting Dynamic Type; `accessibility.md` › Vision / Mobility / Cognitive; `entering-data.md` › Best practices; `privacy.md` › Requesting permission / Protecting data; `settings.md` › Task-specific options. These were read before mapping.
