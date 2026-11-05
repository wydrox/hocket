# Visual direction: a quiet line to Hermes

Hermes Pocket should feel like a direct conversation with an agent the user owns. System typography, generous reading space and restrained native controls keep long responses usable. The one memorable feature is a **route mark beside a text activity label**: two small endpoints joined by a short line, linking connection to the agent's current work. It is a utility signal, never a logo repeated through the transcript.

## Token plan

| Role | SwiftUI / semantic source | Use |
|---|---|---|
| Canvas | `UIColor.systemBackground` | Transcript and root list. |
| Grouped surface | `systemGroupedBackground` / `secondarySystemGroupedBackground` | Settings/forms and attachment groups. |
| Message surface | `secondarySystemBackground` | User bubble and code blocks; no full-screen decoration. |
| Main text | `.primary` / `UIColor.label` | All message content and meaningful status. |
| Supporting text | `.secondary` / `secondaryLabel` | Dates and secondary metadata; validate actual rendered contrast. |
| Action | Semantic `.tint` using system blue | Send, links, interactive toolbar controls. Do not tint static text to resemble a control. |
| Attention | System orange + warning symbol + words | Actual waiting approval or warning, never all work. |
| Error/destructive | System red + error symbol + words | Failed send and truly destructive actions. |
| Dividers | `UIColor.separator` | List structure and code boundaries only where needed. |

No fixed hex palette is specified: overriding semantic Apple colors with their current hex values would defeat appearance/contrast adaptability. This is a deliberate native adaptation of frontend-design's 4–6 named-color template. Asset colors, if later introduced for identity, need light/dark/increased-contrast variants and measured contrast before use. The route mark is neutral/action-tinted according to interactivity, with explicit status text carrying meaning; green is not proof of server health.

Typography uses `.largeTitle` for Threads where the navigation system chooses it, `.headline` for thread titles/section labels, `.body` for transcript/composer (17 pt baseline), `.subheadline` for metadata, and `.caption` only for nonessential details. No light weights. Code uses semantic body text with monospaced design. UI copy follows native title case for control/menu names and sentence case for supporting sentences. Server-provided model/command names retain exact spelling.

Spacing uses a small 4/8/12/16/24 pt rhythm. Prefer native list/form margins, with approximately 16 pt transcript horizontal insets in compact width. Group text with 4–8 pt internal spacing and 16–24 pt between messages by different speakers. Message surfaces use a modest 16 pt corner radius and 12 pt padding; no shadow stack. Layout values are starting constraints, not fixed-height content boxes. Every tap region is at least 44×44 pt; the visible glyph may be smaller.

## Signature behavior

The route mark sits beside text in the conversation subtitle or list header. States: **Connecting…** (native progress indicator), **Connected** (quiet solid line), **Offline** (broken route plus symbol), **Responding** (one restrained state transition), **Approval Required** (attention symbol). The full state is accessible text. Connection status and run status remain independently represented; an online socket cannot prove a running job, and a job can continue server-side while the app is disconnected.

No perpetual pulse, token-by-token shimmer, fake typing dots, sound loops or activity animation in Reduce Motion. A single optional light haptic on confirmed user send can reinforce feedback; no haptic is required to understand state. Agent output ends with quiet confirmation, not confetti. **Feedback Loop**, **Peak-End Rule**.

## Layouts

Compact conversation, planned peak:

```text
┌──────────────────────────────────┐
│ ‹ Threads     Trip Plan       ⋯   │
│       o────o  Responding          │
├──────────────────────────────────┤
│                   You            │
│      [Compare these two PDFs.]    │
│      [plan-a.pdf] [plan-b.pdf]     │
│                                  │
│ Hermes · AI                      │
│ The main difference is…          │
│ Actual streamed content…         │
│                                  │
│ [New Messages]  (only if needed)  │
├──────────────────────────────────┤
│ +  Message Hermes…        [Stop] │
└──────────────────────────────────┘
```

Compact ending:

```text
┌──────────────────────────────────┐
│ ‹ Threads     Trip Plan       ⋯   │
│       o────o  Connected           │
├──────────────────────────────────┤
│ Hermes · AI                      │
│ Complete actual response…        │
│                                  │
│ [Copy] [Share]                    │
│                                  │
│ (No forced follow-up or rating)   │
├──────────────────────────────────┤
│ +  Message Hermes…        [Send] │
└──────────────────────────────────┘
```

Regular iPad:

```text
┌────────────────────┬───────────────────────────────────────────┐
│ Threads      New   │ Trip Plan                  Session     ⋯  │
│ Search             │ o────o Connected                          │
│                    ├───────────────────────────────────────────┤
│ ▸ Trip Plan        │                                           │
│   Compare PDFs     │       Readable transcript column          │
│   Another thread   │       with live real content              │
│                    │                                           │
│                    │       Inline Approval Required            │
│                    │       [Approve Once]  [Deny]              │
│ Settings           ├───────────────────────────────────────────┤
│                    │ +  Message Hermes…                 Send   │
└────────────────────┴───────────────────────────────────────────┘
```

These diagrams describe hierarchy, not custom-drawn navigation controls. Prefer a toolbar Settings action over a bottom sidebar item if it would disappear in short windows. Thread sidebar preferred width about 300 pt, allowed roughly 260–360 pt where space permits. Transcript readable max-width starts near 760 pt and remains leading aligned within a centered content column; wide content can use its own overflow region. Use size classes/available width and native split-view collapse, not device-name checks. At large Dynamic Type, metadata and session summaries stack; actions can move into labelled menus, preserving access.

## Critique before implementation

The initial generic messenger temptation was colorful bubbles plus an always-animated agent avatar. It was removed because neither tells the user whether the service is reachable or whether an action needs approval. The revised mark carries real state; quiet neutral surfaces make long agent responses legible. No hero, gradient, dashboard cards, serif display, all-caps micro-labels or decorative status metrics are relevant to this job. System type is intentionally the voice of a native working tool; distinctiveness is spent in one small state element.

Native materials belong to the system's navigation/control layer. Keep message content solid and readable. Do not hand-build imitation glass over text. Follow system dark appearance, Increase Contrast, Reduce Transparency and Reduce Motion without adding redundant app-level toggles.

Basis: `color.md` › Best practices / System colors, `typography.md` › Using system fonts / Supporting Dynamic Type, `layout.md` › Visual hierarchy / Adaptability, `accessibility.md` › Vision / Cognitive, `designing-for-ios.md` › Best practices, `loading.md` › Showing progress, and `generative-ai.md` › Outputs. Screenshot, contrast and touch-target validation remain pending until the UI runs.
