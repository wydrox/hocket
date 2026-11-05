# Flow specification: hocket

## 0. Context

- **User and job:** an existing Hermes user wants to resume work, send text/files, adjust agent settings, and handle agent actions directly on iPhone or iPad.
- **Entry:** app launch, returning thread, optional later notification/deep link. Promise: connect to the user's real Hermes service.
- **Entry emotion:** often rushed or checking on a long task. Keep work visible and avoid tours. **Cognitive Load**.
- **User success:** a verified connection and an actual server-acknowledged message/response in the intended thread, with accurate delivery and approval state.
- **Product success:** reliable task completion and fewer trips back to Telegram. No engagement quota, forced notification opt-in, or monetization objective.
- **Constraints:** SwiftUI, iOS/iPadOS, HTTPS and server authentication, Keychain, actual contract capabilities. Initial copy is English with localization-ready strings; no app-specific override for system appearance/text size.
- **Assumptions:** user has a Hermes endpoint and access token. Server is authoritative for thread IDs, message IDs, supported controls, effective settings, approvals and command outcomes. A local fallback may search downloaded data, clearly labelled “On This Device”. It cannot pretend to search the server.

## 1. Experience targets

- **Peak:** the first real response appears beneath the user's sent message while a concise activity label makes the state clear. **Peak-End Rule**.
- **End:** completed output remains selectable and shareable, partial failures remain labelled, and the composer is ready. No success celebration for an unacknowledged request.
- **User takeaway:** “I can talk to my Hermes agent and see what it needs from me.”
- **Negative peaks:** invalid token, wrong endpoint, lost draft, duplicate send, disconnected stream mistaken for completion, missing approval, inaccessible composer. Handle these before adding ornament. **Negativity Bias**.
- **First-use length:** connect, choose/create thread, send; three meaningful actions. Do not invent an elapsed-time estimate or progress percentage. Connection is one form and an actual request, so a multi-step onboarding progress bar is unnecessary.

## 2. Information architecture

Ranked tasks: 1. resume/read a conversation; 2. send text or attachments; 3. resolve agent requests; 4. adjust the active session; 5. find/run a command; 6. manage connection/privacy.

Threads is the root and Chat is its detail. A two-column `NavigationSplitView` adapts to native single-column navigation. A Settings toolbar action opens a short sheet/stack. Commands are reachable from the composer and slash entry; Help is in Settings. Do not add tabs merely to fill a navigation template: the content is a single list/detail hierarchy. **Mental Model**, **Progressive Disclosure**.

- L1: selected thread, messages, composer, send/stop, actual activity state, pending approval.
- L2: attachment picker, searchable Commands, Session options, conversation actions, search.
- L3: connection credentials, app lock, privacy/cache management, diagnostics without secrets.
- Vocabulary: “Threads”, “Message”, “Model”, “Reasoning Effort”, “Service Tier”, “Connection”, “Approval Required”. Keep server names/IDs exact in detail views.

## 3. Flow map

```text
Launch → Saved valid connection → Threads → Chat → Send → Server response → Ready
   └── No connection → Connect → Actual validation ──┘
                           └── Failure → Edit / Retry
Chat → Add Attachment → Review / Remove → Send
Chat → Session Options → Save → Read back effective settings → Chat
Chat → Commands → Review arguments → Run → Actual result in Chat
Chat → Approval Required → Review → Approve / Deny → Actual resolution
Any network request → Disconnected → Preserve draft/content → Retry / Reconnect
```

| Step | Goal | Ask / value | Principle | Exit |
|---|---|---|---|---|
| Connect | Reach own agent | Endpoint and token / actual validation | **Feedback Loop** | Leave app; edit freely |
| Threads | Resume intended work | Select or create / real history | **Recognition Over Recall** | Settings or leave |
| Chat | Communicate | Message/files / persistent result | **Mental Model** | Back without losing draft |
| Session | Control execution | Supported choices / effective values | **Default Bias** | Cancel without mutation |
| Command | Discover capabilities | Arguments / actual command result | **Recognition Over Recall** | Cancel preserves composer |
| Approval | Decide a consequential action | Approve or deny / verified resolution | **Feedforward** | Leave pending; never autoapprove |

## 4. Screen specifications

Shared states: “Loading…” is temporary with a native progress indicator; after a longer wait show a truthful noun/verb such as “Loading Threads…” or “Waiting for Hermes…”. Never fabricate execution steps or percentages. Empty/loading/partial/error/success states below apply independently: stale content may remain usable alongside an error. Every action gives immediate local feedback; network completion requires server acknowledgement. **Feedback Loop**.

### 1 — Connect to Hermes

Purpose: validate the user's actual service. Primary action: **Sign In**, below a single-column form with **Server Address**, **Username**, and **Password**. Native Basic-provider PKCE exchanges credentials for Keychain-stored access and refresh tokens. **Advanced Connection** offers **Use an Access Token** and changes the primary action to **Connect**. Copy: “Messages and attachments are sent to this server. Your sign-in token is stored in this device’s Keychain.” Passwords are never persisted.

Defaults: saved nonsecret endpoint only. Never reveal a stored token. Paste uses explicit user action; no clipboard polling. URL keyboard, autocorrection/capitalization disabled; HTTPS required for saved production endpoints. Do not add a global ATS exception. Explicit local-development access, if needed, must be separately scoped and documented.

States: empty fields with example `https://hermes.example.com`; invalid URL “Enter a valid HTTPS server address.”; loading **Connecting…** disables duplicate requests, retaining form; TLS failure “The server’s secure connection could not be verified. Check its address and certificate.”; unauthorized “The server rejected this token. Check the token and try again.”; unreachable “Couldn’t reach Hermes. Check the address and your connection, then try again.”; partial validation “Connected, but threads couldn’t be loaded.” with Retry; success moves to Threads with **Connected** state. Do not treat a TCP connection as authentication success.

Trust: show full host next to the token field so the destination is apparent. Screen reader labels are persistent, URL error is associated with its field, and focus moves to the first error. **Cognitive Load**, **Feedback Loop**.

### 2 — Threads

Purpose: resume or create work. Primary action: **New Thread** (`square.and.pencil` labelled for accessibility). Hierarchy: “Threads”; connection capsule; search; recent threads with server title, useful last-message preview, actual update time, unread/run state when known; Settings toolbar action.

Defaults: most recently selected real thread, recent activity order only if supported by source data. No synthetic sample conversations. Selection remains stable through refresh; no jump caused by streaming deltas.

States: empty “No Threads Yet” / “Start a conversation with Hermes.” / New Thread; loading skeleton rows only while fetching; partial cached rows plus “Showing Saved Threads” and last refresh time; error “Threads couldn’t be loaded.” / Retry; search empty “No Matching Threads” / “Try another word.”; success real rows and selection. Search scope says **On This Device** if limited to downloaded titles/history. No delete/archive gesture unless implemented server-side; prefer rename/archive with Undo where truly reversible.

Accessibility: whole row is a button with title, preview, date and state grouped sensibly; timestamps do not outrank title. Dynamic rows expand. **Recognition Over Recall**, **Progressive Disclosure**.

### 3 — Conversation

Purpose: send and understand agent output. Primary action: **Send Message**; while a cancellable run is active, **Stop Response** replaces it only if supported. Hierarchy: server thread title; compact connection/activity capsule; chronological transcript; inline approvals/tool summaries; staged attachments; multiline message composer; Add Attachment; Send. Session options are a labelled toolbar/menu action with the effective model shown compactly when known.

Transcript: use readable leading-aligned assistant content; quieter trailing user bubbles with role/accessibility labels. Distinguish “You” and “Hermes · AI”. Render safe supported Markdown, selectable text, code with Copy, links with normal system handling, attachment preview/download where real. Never run commands embedded in assistant text. Wide code can scroll horizontally inside its own region. Keep chronological IDs stable as deltas arrive.

Composer defaults: no invented prompt, server default session, local draft per actual thread. Placeholder **Message Hermes** with a persistent accessibility label. Newlines insert newlines; explicit Send or Command-Return sends on iPad. Enter does not unexpectedly submit dictated or pasted text. Optional command suggestion list opens from **Commands** or slash entry and never replaces text without selection.

States: empty “Start a Conversation” / “Send a message or add an attachment.”; sending shows pending bubble labelled **Sending…**; acknowledged bubble becomes **Sent**; streaming shows actual content plus **Responding**; waiting shows **Working** only when reported by server; approval shows **Approval Required**; completed removes activity, retains output; failed send **Not Sent** with Retry and edit; lost stream **Connection Interrupted** / “Your message may have reached Hermes. Reconnect to check before sending again.”; partial result **Response Incomplete**, preserving text; cancelled **Response Stopped** only after acknowledgement (or clearly **Stop Requested** while waiting). If stop unsupported, expose that in Help and do not show a nonfunctional stop button.

Scrolling: follow new content only when the reader is already near the end. Otherwise show **New Messages**; do not steal reading position or VoiceOver focus for every token. Announce meaningful state changes, batch message announcements. Send success clears draft only after correct acknowledgement. Retry reuses a client request ID where supported; without idempotency, reconcile history before retry. **Feedback Loop**, **Negativity Bias**.

### 4 — Attachment review

Purpose: choose what the user will send. Primary action: **Add to Message** if a separate preview is needed; otherwise the picker stages items directly and Chat owns Send. Menu options appear only when implemented: **Photos**, **Take Photo**, **Files**, **Scan Document**, **Record Audio**. OS keyboard dictation remains available without adding a custom microphone flow.

Show name/type/size, available thumbnail, recipient host/thread context, and explicit Remove. Exact supported formats/count/size come from the contract; validate before send. Never upload on selection without explaining that behavior. Prefer local staging and upload during Send. Strip unnecessary location metadata where feasible; explain any media conversion that changes the file.

States: empty “Choose a Photo or File”; importing “Preparing Attachment…”; partial per-item progress; unsupported “This server doesn’t support this file type.”; oversized “This file exceeds the server’s {limit} limit.”; denied permission offers **Open Settings** and **Choose File** where applicable; upload error **Upload Failed** / Retry or Remove; ready **Ready to Send**; successful send shows the server attachment record. Removing a staged item does not delete the source. **Feedforward**, **Fitts's Law**.

### 5 — Session options

Purpose: control the active conversation without leaving it. Primary action: **Save Changes**, with **Cancel**. Title **Session Options**; grouped **Model**, **Reasoning Effort**, **Service Tier**; brief copy “Options are provided by your Hermes server.”; current/effective value alongside pending choice. Use exact server IDs in secondary text when display names are ambiguous.

Defaults: **Server Default** means omit a client override, not assume a particular model, effort or tier. Only populate supported values and combinations. If the server provides current values without an option catalog, display those values read-only until a validated selection flow exists; never guess `low/medium/high` or provider-specific service-tier values. Explain the server's advertised scope: **Applies to This Thread** or **Applies to New Messages** only when known.

States: loading **Loading Options…**; absent capability “This server doesn’t expose session options.”; partial **Model Available; Other Options Unavailable** only for actually available fields; unsupported combination inline beside relevant field; saving **Saving…**; failure “Options weren’t saved. Try again.” retains pending selections; success **Changes Saved** after server readback. If a value is changed concurrently, show actual effective values and allow re-selection. No silent fallbacks or invented cost/speed promise. **Default Bias**, **Progressive Disclosure**.

### 6 — Commands and Help

Purpose: discover real agent capabilities. Primary action after selection: **Run Command** or the server's exact action name. Searchable list shows command name, description and required arguments; read-only commands may run immediately if clear, mutating commands open argument/review view. Keep native actions such as New Thread separate from server commands.

States: loading **Loading Commands…**; empty “No Commands Available” / “This server hasn’t provided a command list.”; search empty **No Matching Commands**; partial cached list explicitly stale and revalidated before consequential execution; invalid argument explained beside field; running **Running {command}…**; actual result **Command Completed** only on success; failure “The command didn’t complete.” plus a safe server reason and Retry. Preserve arguments on error. Without a catalog, Help can explain known verified capabilities; do not invent a command index. **Recognition Over Recall**, **Feedforward**.

Help explains setup, attachment constraints, settings scope, AI fallibility, background limitations, and how to revoke a token. Never claim iOS keeps a live connection running indefinitely. Diagnostics redact token/message/attachment content by default.

### 7 — Approval required

Purpose: understand and decide a server-requested action. The decision is deliberately symmetrical: **Approve Once** and **Deny** have equally legible targets; neither is preselected. The usual one-primary-action guideline yields to the ethics gate here. Hierarchy: “Approval Required”; exact proposed action and destination; consequences and server context; optional expandable technical details; both decisions; pending/resolved status.

States: unavailable details **Approval Details Unavailable** / Refresh, with no blind Approve; pending can be left untouched; resolving **Sending Decision…** prevents duplicates; expired **Request Expired**; concurrent resolution **Already Resolved** with actual outcome; failure “Your decision wasn’t confirmed. Refresh to check its status.”; success **Approved Once** or **Denied** after acknowledgement. Persist an auditable inline outcome. Approval never hides solely in an ephemeral notification, swipe, or color. Do not offer “Always Approve” without a real scoped server policy and separate reviewed design. **Feedforward**, **Negativity Bias**.

### 8 — Settings and connection management

Purpose: manage server and local privacy. Primary action is contextual: **Save Connection** on edit; otherwise Settings is navigation, not an artificial call to action. Sections: **Connection** (host and status, Replace Token, Disconnect), **Privacy** (App Lock if real, Clear Local Data), **Help**, **About** (version/build). Token remains obscured and is never copied/exported in diagnostics. Replacing endpoint or token is tested before switching the active connection.

States: empty connection offers Connect; validating **Checking Connection…**; partial offline cached settings marked **Offline**; save error preserves the old working configuration; success confirms **Connection Updated**; disconnect warns that this removes local access but does not revoke the server token or delete server conversations. Clearing local data lists affected drafts/cache and preserves or separately confirms Keychain removal. Device lock uses system authentication and never promises independent server protection.

Permissions: Photos uses the system picker, Files uses document picker, camera/mic prompts occur only on chosen action. Example actual usage strings: “Take photos to attach to your Hermes messages.” / “Record audio to attach to your Hermes messages.” Request no contacts/calendar/location access without a specific real feature. Direct OS permission prompts avoid a persuasive pre-permission modal. **Default Bias**, **Provide Exit Points**.

## 5. Ending design

Connection ends with **Connected** and real Threads, not a marketing screen. Sending ends with the actual output plus completed/stopped/failed state, available Copy/Share, and the intact next-message composer. User credit is the sent message itself. Routine chat needs no confetti. Optional next action is another message; Back or leaving the app is a valid exit. Notification follow-through is only offered after successful use and only when an actual delivery path exists, with generic “Hermes finished responding.” previews by default. No forced feedback prompt. **Peak-End Rule**, **Provide Exit Points**.

## 6. Emotional journey (design prediction, not study result)

| Step | Expected emotion −2…+2 | Driver / mitigation |
|---|---|---|
| Connect | −1 → 0 | Existing credentials required; only two inputs with inline recovery. |
| Threads | +1 | Familiar work appears, no sample data confusion. |
| First send | +1 | Pending delivery state, draft protection. |
| Stream / wait | 0 → +1 | Actual progress; can read and navigate. |
| Approval | −1 → 0 | Consequences visible, symmetric decisions, no timeout pressure. |
| Complete | +2 | Durable actual output, selectable/exportable. |
| Disconnect | −1 → 0 | Existing output and draft remain, safe reconciliation path. |

## 7. Ethics gate

| Element | Principle | Transparency | Symmetry | Reversibility | Alignment | Verdict |
|---|---|---|---|---|---|---|
| Server defaults | **Default Bias** | Actual origin labelled | Change/reset equally reachable | Reset override supported or limitation stated | Avoid invented costly upgrades | Pass in spec |
| Stream/activity | **Feedback Loop** | States reflect actual events | Stop/leave visible when supported | Draft and partial output preserved | Reduces uncertainty | Pass in spec |
| Approvals | **Feedforward** | Exact action/context shown | Approve and Deny equal access | Consequences disclosed when irreversible | User remains decision maker | Pass in spec |
| Attachments | **Mental Model** | Preview, destination, size shown | Remove as easy as add | Staging undo; server deletion scope disclosed | Deliberate sharing | Pass in spec |
| Return notifications | **Provide Exit Points** | Only real useful completion | Opt-in; OS opt-out | Revocable permission | No retention nagging | Pass in spec |

User satisfaction decisions are draft safety, reliable delivery, accessible reading and agent control. There are no conversion moves. Irreversible actions cannot satisfy literal undo; the design discloses this before a deliberate decision instead of claiming reversibility. No fabricated scarcity/progress, false human identity, prechecked paid settings, secret telemetry, or guilt copy. Shipping implementation must rerun the gate.

## 8. Validation plan

Before testing: predict users can locate an existing thread, attach a file, open session options, and find a command within two navigational actions; no draft disappears on retry or resize; an interrupted stream is never mistaken for completed output. Verify invalid-token recovery, uncertain send outcome, stale session settings, absent capabilities, approval expiry and permission denial as first-class paths.

Use real native screenshots and device/simulator interaction on small/large iPhone, iPad regular width and narrow resizable window; largest Dynamic Type, VoiceOver, keyboard, light/dark/increased contrast/reduced motion. Study failed attempts as well as successful ones with neutral task instructions. Metrics, if explicitly implemented with privacy consent: connection completion, send completion, time to first actual response, retry/duplicate rate, lost drafts, unhandled approvals. Do not install analytics merely to measure the design.
