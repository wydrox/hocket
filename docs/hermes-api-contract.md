# Hermes native iOS API contract

Discovery date: 2026-11-05. Source root: `/Users/rafalw/.hermes/hermes-agent`.
Inspected source commit and running gateway `code_sha` both equal
`d49e2ebbaed42718659c13f82c04cde7d8ab10bd`; running gateway reports version `0.22.5`.
All examples below are dummy data. Discovery did not submit prompts, read chat histories,
retrieve credentials, restart services, or change Hermes configuration.

## Connection and authentication

Use the structured JSON-RPC WebSocket `/api/ws`, with canonical session authority
`hermes-gateway-v1`. Do not build native chat on the raw terminal `/api/pty` or the
stateless OpenAI compatibility endpoint. The canonical owner provides durable prompt
admissions, revision-fenced edits, execution generations, and replay.

Sources: `gateway/session_contract.py:9`, `hermes_cli/web_routers/chat_ws.py:650`,
`tui_gateway/ws.py:364`, `gateway/session_controls.py:173`.

The WebSocket first sends:

```json
{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"skin":{},"change_events":true,"heartbeat":true,"replay_epoch":"opaque","session_authority":true}}}
```

Require `session_authority:true` for this implementation. Call `runtime.describe {}`
and inspect the returned `instance_id`, `profile_id`, `authority_epoch`,
`capabilities`, and `session_create:{sources,parameters}`. `desktop_protocol` in
session snapshots is `hermes-gateway-v1`. Use only declared source/parameter values;
`gui` is the appropriate current native client source.

Sources: `tui_gateway/ws.py:548`, `tui_gateway/contracts/events.py:51`,
`tui_gateway/contracts/canonical.py:331`, `tui_gateway/contracts/canonical_sessions.py:21`.

HTTP authentication supports `X-Hermes-Session-Token` or `Authorization: Bearer …`
for the private legacy session token. On a gated remote listener, user access
tokens are verified by session providers; an ephemeral private `_SESSION_TOKEN`
does not substitute for that login. The private `X-Hermes-Gateway-Ticket` bootstrap
is local-process/loopback oriented and must not be copied to an iPhone as a standing token.
Do not expose a local listener by tunneling it without configuring the remote auth/host gate.

Sources: `hermes_cli/web_server.py:299`, `hermes_cli/dashboard_auth/native_http.py:191`,
`hermes_cli/web_server_chat.py:201`, `hermes_cli/dashboard_auth/middleware.py:29`.

Remote sign-in endpoints:

| Method and route | Input / output |
|---|---|
| `GET /api/auth/providers` | Public provider metadata for sign-in bootstrap. |
| `GET /auth/native/authorize` | Query `provider` optional, `code_challenge`, `code_challenge_method=S256`, `redirect_uri`, `state`. Opens normal provider login. |
| `POST /auth/native/token` | JSON `{code,code_verifier}` → `{access_token,refresh_token,token_type:"Bearer",expires_at,provider}`. Code is single use. |
| `POST /auth/native/refresh` | JSON `{refresh_token,provider}` → rotated token payload; 401 `session_expired` or 503 when provider unavailable. |
| `GET /api/auth/me` | Authenticated identity projection. |
| `POST /api/auth/ws-ticket` | Authenticated request → `{ticket,ttl_seconds:30}`; one use per WS. |
| `POST /api/webapp/socket-ticket?socket=gateway&profile=…` | Webapp-specific purpose-bound gateway ticket, where surface permits it. |

Sources: `hermes_cli/dashboard_auth/routes.py:211`, `hermes_cli/dashboard_auth/routes.py:297`,
`hermes_cli/dashboard_auth/routes.py:531`, `hermes_cli/dashboard_auth/routes.py:563`,
`hermes_cli/dashboard_auth/routes.py:585`, `hermes_cli/dashboard_auth/routes.py:606`,
`hermes_cli/web_routers/webapp.py:227`.

Use a fresh WS ticket with `/api/ws?ticket=…`, or offer both subprotocols
`hermes-gateway-v1` and `hermes-gateway-ticket.<ticket>` where that socket ticket
path supports them. This avoids putting a standing access token in a URL.
The source also supports gated `/api/ws?token=<user-access-token>` for remote
desktop compatibility, but native logs must never persist that URL.

Sources: `hermes_cli/web_server_boundary.py:156`, `hermes_cli/web_server_chat.py:201`.

**iOS login gap:** the native authorization route only allows a canonical HTTP
loopback redirect (`127.0.0.1` or `[::1]`), and rejects app URL schemes and universal
links. The current broker targets desktop system-browser + local-listener login.
An iOS ASWebAuthenticationSession OAuth flow needs a separately reviewed callback
extension to Hermes or a local callback listener. The existing `basic` password
provider has a working native PKCE adaptation: its password-login JSON returns
the code-bearing callback as `next`, which the app can validate and parse locally
without navigating. See [mobile-connection-plan.md](mobile-connection-plan.md).
Do not claim that existing desktop browser OAuth automatically works on iOS.

Source: `hermes_cli/dashboard_auth/routes.py:250`.

Store tokens in Keychain; do not bundle tokens, model-provider keys, or server
configuration. Accept a user-entered HTTPS origin, use WSS, and refuse credentials
in URL userinfo/query on the connection form. Private tailnet HTTPS is suitable
when both devices are in the user's tailnet and the upstream Hermes listener is
correctly authenticated. Do not disable TLS verification or add broad ATS exceptions.

## Wire and connection lifecycle

Client sends one JSON-RPC 2.0 object per WS text message. Server writes serialized
newline-delimited objects, currently one `send_text` per serialized frame; its
coalescing batches scheduling without combining JSON objects. Accept trailing
newlines and decode each nonempty line for shared-transport compatibility. Keep RPC IDs
separate from durable `request_id` / `submission_id` values.

```json
{"jsonrpc":"2.0","id":"rpc-1","method":"runtime.describe","params":{}}
{"jsonrpc":"2.0","id":"rpc-1","result":{"instance_id":"example","profile_id":"example-profile","authority_epoch":1,"capabilities":[],"session_create":{"sources":["gui"],"parameters":[]}}}
```

`gateway.ping` with an ID returns `{ok:true}` independently of a busy command.
Shared clients use a 15-second heartbeat and a 45-second deadline. After
`gateway.ready`, advertise `client.capabilities {server_requests:true}` so prompts
can be answered. Do not advertise desktop-local hardware bridges on an iPhone.

Sources: `tui_gateway/ws.py:169`, `tui_gateway/ws.py:260`, `tui_gateway/ws.py:605`,
`apps/shared/src/json-rpc-channel.ts:535`, `tui_gateway/AGENTS.md`.

Normal response: `{jsonrpc,id,result}`. Refusal:
`{jsonrpc,id,error:{code:4001,message:"reason",data:{reason,field?,detail?,revision?,execution_generation?}}}`.
Unknown method is `-32601`; parse error `-32700`; storage unavailable `5001`.
Do not silently treat an unknown method as success. Refetch snapshot on a stale
revision/generation rather than changing the fence and automatically repeating
a destructive action.

Source: `gateway/session_controls.py:20`, `gateway/session_controls.py:244`,
`gateway/session_controls.py:300`.

## Threads, history, and prompt admission

Hermes calls conversations **sessions**. Use `(profile_id,session_id)` as identity;
IDs alone do not isolate profiles. A snapshot contains `session_id`,
`stored_session_id`, `messages`, `message_count`, `running`, `authority_epoch`,
`replay_epoch`, `last_sequence`, `subscription_id`, `revision`,
`execution_generation`, `pending`, `prompts`, `info`, optional `open_requests`,
`pending_connection`, and `todo_state`.

Sources: `tui_gateway/contracts/canonical_sessions.py:77`,
`tui_gateway/contracts/canonical_sessions.py:137`.

| RPC | Parameters and result |
|---|---|
| `session.create` | `{request_id,source:"gui",title?,cwd?,model?,provider?,reasoning?,service_tier?,profile?}` → snapshot. Omit host cwd unless deliberately selected. Persist request ID across lost-ACK retry. |
| `session.list` | `{scope:"stored",limit:200,title?,include_hidden:false,profile?}` → `{sessions,scope}`. Default is **live**, so explicitly select stored for thread history. Rows include `session_id,id,title,source,started_at,message_count,running,model?,resolved_id?,root_title?`. |
| `session.resume` | `{session_id,profile?,omit_messages?,defer_history?,display_projection?}` → snapshot and attached subscription. |
| `session.info` | `{session_id}` → frozen policy/model/reasoning/tier and inventory. |
| `session.history` | `{session_id,profile?}` → display transcript from owner, compression ancestors included. |
| `session.detach` | `{session_id,subscription_id,end_reason?}` → `{session_id,subscription_id,detached}`. Omit end_reason when merely navigating away. |
| `prompt.submit` | `{session_id,text,submission_id,input_id?,queued?,attachments?,clarify_batch?}` → admission receipt. |
| `prompt.receipt` | `{session_id,admission_id,include_result?}` → current receipt, optional terminal result/usage. |
| `prompt.cancel` | `{session_id,admission_id}` → receipt; cancels queued work or interrupts started work. |
| `session.interrupt` | `{session_id,execution_generation,profile?}` → session handle. |
| `session.steer` / `session.redirect` | `{session_id,execution_generation,text,profile?}` → correction acknowledgement. |
| `prompt.steer_queued` | `{session_id,admission_id,profile?}` → receipt; use only when row controls advertise `steer`. |
| `prompt.replace_queued` | `{session_id,admission_id,submission_id,text,attachments?,profile?}` → new admission at FIFO tail. |

Sources: `tui_gateway/contracts/canonical_sessions.py:21`,
`tui_gateway/contracts/canonical_sessions.py:58`, `tui_gateway/contracts/canonical_sessions.py:162`,
`tui_gateway/contracts/canonical_sessions.py:207`, `tui_gateway/contracts/canonical_sessions.py:248`,
`tui_gateway/contracts/canonical.py:28`, `tui_gateway/contracts/canonical.py:314`,
`gateway/session_tui_ops.py:121`.

An admission receipt contains `admission_id`, `ref:{profile_id,session_id}`,
`sequence`, `status:queued|started|unknown|terminal`, `outcome`, `authority_epoch`,
`execution_generation`. Acceptance does not mean completion. Keep one durable
submission ID for retries of the exact same prompt; do not resubmit after a
timeout with a new ID. `unknown` after owner restart requires explicit
`prompt.resolve_unknown {session_id,admission_id,execution_generation}`; this
acknowledges loss and resumes followers without re-running that input.

Sources: `tui_gateway/contracts/canonical.py:28`, `tui_gateway/contracts/canonical.py:68`.

`session.mutate` is the canonical edit API:

```json
{"jsonrpc":"2.0","id":"rpc-2","method":"session.mutate","params":{"session_id":"example-session","request_id":"mutation-uuid","expected_revision":4,"operation":"rename","payload":{"title":"Example thread"}}}
```

Operations include `rename {title}`, `archive {archived}`, `sidebar` metadata
(`title,archived,hidden,pinned,unread`), `delete {}`, `reset {}`, `branch`, `rewind`,
`compress`, `model`, `reasoning`, and `workspace`. Delete/reset/branch/rewind/model/
compress/reasoning/workspace require `expected_generation` in addition to
`expected_revision`. Use a unique retry-stable mutation request ID.

Sources: `tui_gateway/contracts/canonical.py:81`, `hermes_state_mutations.py:5`,
`hermes_state_mutations.py:40`, `hermes_state_mutations.py:49`.

For paged stored history, REST complements the subscription:

| Route | Details |
|---|---|
| `GET /api/sessions?limit=20&offset=0&order=recent&archived=exclude&profile=…` | Limit 0–100; archived `exclude|only|include`; source filtering; returns sessions/total/limit/offset plus storage metadata. |
| `GET /api/sessions/{id}/messages?limit=100&offset=0&order=latest&inline_images=false&profile=…` | Max 500; includes compression ancestors; returns session_id/profile/messages/pagination. Default omitted limit fetches newest 500. |
| `GET /api/sessions/{id}/mutation-snapshot?profile=…` | Read current edit fences for a stored row. |
| `GET /api/sessions/search` | Search endpoint; inspect actual query contract before wiring search. |
| `GET /api/sessions/{id}/timeline` | Durable transcript navigation endpoint. |
| `GET /api/sessions/{id}/export` | JSON export; canonical `session.export` also supports json/md/html/snapshot client-written content. |

Sources: `hermes_cli/web_routers/sessions.py:182`, `hermes_cli/web_routers/sessions.py:286`,
`hermes_cli/web_routers/sessions.py:586`, `hermes_cli/web_routers/sessions.py:739`,
`hermes_cli/web_routers/sessions.py:801`, `hermes_cli/web_routers/sessions.py:941`,
`tui_gateway/contracts/canonical.py:270`.

## Streaming, replay, tools, and prompts

```json
{"jsonrpc":"2.0","method":"event","params":{"type":"message.delta","session_id":"example-session","payload":{"text":"Hello"},"replay_epoch":"session-epoch","seq":8,"authority_epoch":1,"execution_generation":2,"admission_id":"example-admission"}}
```

Preserve session-specific `(replay_epoch,seq)` cursors. `message.delta.text` can be
null at a segment boundary. Append normal delta text. On `message.complete`,
reconcile the full final text rather than append it to streamed text. Its optional
`response_reused` means the text was already delivered. `persisted_turn` supplies
durable row IDs and the submission ID for optimistic-bubble reconciliation.

Sources: `tui_gateway/contracts/canonical_sessions.py:293`,
`tui_gateway/contracts/events.py:135`, `tui_gateway/contracts/events.py:251`.

Reconnect: attach/resume, then `session.events.since {session_id,last_sequence,replay_epoch}`.
Result includes `events,latest_seq,last_sequence,epoch,replay_epoch,truncated,
snapshot_required,count,open_requests?`. If snapshot required, replace local
projection with a fresh resume snapshot; deduplicate replay by seq. Do not compare
a session cursor to the process-global `gateway.ready` replay epoch.

Source: `tui_gateway/contracts/canonical_sessions.py:293`,
`apps/shared/src/json-rpc-gateway.ts:585`.

Relevant event payloads:

| Event | Payload |
|---|---|
| `message.start` | Optional text/display metadata for turn. |
| `message.delta` | `{text:string|null,rendered?,verbose?}`. |
| `message.complete` | `{text,usage?,status?,reasoning?,warning?,error?,recoverable?,failure_reason?,persisted_turn?,…}`. |
| `reasoning.delta` / `reasoning.available` / `thinking.delta` | `{text,rendered?,verbose?}`; allow collapsed reasoning. |
| `tool.start` | `{tool_id,name,context?,args?,args_text?,preview?,labels?}`. |
| `tool.generating` | `{name}`. |
| `tool.progress` | `{tool_id,name,progress,total?,percent?,message?}`. |
| `tool.complete` | `{tool_id,name,args?,duration_s?,result?,summary?,result_text?,inline_diff?,todos?,revision?,labels?}`. |
| `tool.output_risk` | `{tool_id,name,risk,findings,redacted}`. |
| `approval.request` | `{kind:"approval",prompt_id,execution_generation,command,description,choices,edit?,timeout_s?}`. |
| `clarify.request` | `{kind:"clarify",prompt_id,execution_generation,question,choices,multi_select?,timeout_s?}`. |
| `approval.settled` / `clarify.settled` | `{prompt_id,execution_generation}`; remove waiting card. |
| `session.usage` / `session.title` / `status.update` | Keep model/context/usage/thread-title UI current. |
| `sessions.changed` / `skills.changed` | Refresh thread list / slash catalog. |

Sources: `tui_gateway/contracts/events.py:135`, `tui_gateway/contracts/events.py:296`,
`tui_gateway/contracts/events.py:345`, `tui_gateway/contracts/events.py:387`,
`tui_gateway/contracts/events.py:844`, `gateway/session_pending_controls.py:18`.

Use returned approval choices exactly; typically `once,deny,session,always`, with
restricted edit approvals only `once,deny`. Answer `approval.respond
{session_id,execution_generation,prompt_id,choice}` or `clarify.respond
{session_id,execution_generation,prompt_id,answer}`. Empty clarify answer skips.
Do not synthesize approval acceptance from UI dismissal.

Sources: `tui_gateway/contracts/canonical_sessions.py:288`,
`tui_gateway/contracts/canonical.py:355`, `gateway/session_pending_controls.py:18`.

The server also sends **JSON-RPC requests**, not just `event` notifications:

```json
{"jsonrpc":"2.0","id":"srq-example","method":"sudo","params":{"session_id":"example-session","command":"example command"}}
{"jsonrpc":"2.0","id":"srq-example","result":{"value":""}}
```

Support masked `sudo`, `secret`, vault prompts, and batch `clarify` with explicit
skip/cancel. `clarify` request fields are `{session_id,questions:[{qid,question,
choices?,multi_select?}],answers?}`; response `{answers:{qid:"answer"},outcome:"submitted"}`.
Unsupported desktop hardware/UI requests should be explicitly declined, not
auto-approved. Restore `open_requests` after reconnect. Sensitive answers go only
in response frames; never persist them in transcript/cache/analytics.

Sources: `tui_gateway/contracts/server_requests.py:20`,
`tui_gateway/contracts/server_requests.py:166`, `gateway/session_server_requests.py:1`.

## Attachments

Images: call `image.attach_bytes {session_id,content_base64,filename}` (or `data`
alias). Result `{attached:true,path,mime,name,count:1,remainder:"",text,bytes}` is
staging-only on canonical sessions. Include returned `{path,mime}` explicitly
in `prompt.submit.attachments`. Max 10, PNG/JPEG/GIF/WebP, magic-byte validation;
base64 upload cap is 25 MiB and gateway admission aggregate byte limit can be lower.
Never send a local iPhone filesystem path as a gateway path.

```json
{"jsonrpc":"2.0","id":"rpc-3","method":"prompt.submit","params":{"session_id":"example-session","submission_id":"input-uuid","text":"Describe this image.","attachments":[{"path":"/example/profile/cache/images/upload_example.png","mime":"image/png"}]}}
```

Sources: `gateway/session_images.py:8`, `tui_gateway/prompt_attachments.py:21`,
`gateway/session_ingress_media.py:131`, `tui_gateway/contracts/canonical_sessions.py:187`.

Documents/PDF/other files: call `file.attach {session_id,data_url:"data:application/pdf;base64,…",
name:"example.pdf"}`. Result `{attached,name,path,ref_path,ref_text,uploaded}`.
Append exact returned `ref_text` (`@file:…`) to the next prompt text. This is a file
reference the server-side agent reads, rather than an image attachment array.
The return does not start inference. For larger files prefer multipart
`POST /api/chat/file-upload` with field `file` and optional query `profile`; response
`{ok,path,size,staged_upload?}`. Pass that opaque receipt into
`file.attach {session_id,staged_upload,name}`. The browser staging cap is 16 MiB.

Sources: `gateway/session_ancillary.py:138`, `tui_gateway/contracts/prompt_voice.py:178`,
`tui_gateway/prompt_attachments.py:270`, `hermes_cli/web_routers/uploads.py:22`,
`hermes_constants.py:29`.

Downloads: authenticated `GET /api/fs/download?path=…&session_id=…&profile=…`
resolves session workspace ownership; GET/HEAD supported. Managed-file routes
include `GET /api/files`, `/api/files/read`, `/api/files/download`,
`/api/files/stream` (Range media), JSON `POST /api/files/upload {path,data_url,overwrite}`,
and multipart `/api/files/upload-stream {file,path,overwrite}`. Managed uploads
are 100 MiB capped, distinct from chat attachment staging. Prefer chat file upload
for composer picks: it does not let the client choose an arbitrary host path.

For browser/media URLs, authenticated `POST /api/files/ticket
{route:"download"|"stream",path,profile?,session_id?}` gives `{ticket}` bound to
the exact request and file. Download ticket single use; stream ticket reusable
until expiry. Use native authenticated requests where available instead of putting
standing access tokens in file URLs. Server file permissions can return 403/404.

Sources: `hermes_cli/web_routers/files.py:759`, `hermes_cli/web_routers/files.py:806`,
`hermes_cli/web_routers/files.py:873`, `hermes_cli/web_routers/files.py:927`,
`hermes_cli/web_routers/files.py:1328`, `hermes_cli/web_server.py:653`,
`hermes_cli/web_server_file_tickets.py:1`.

## Slash commands and model controls

`commands.catalog {session_id?,profile?}` → `pairs,sub,canon,commands,categories,
skills,skill_count,warning,plugin_discovery_error,plugin_commands`. Build a searchable
palette from this metadata; catalog presence is not execution support.
`complete.slash {text,session_id?,profile?}` returns `{items,replace_from?}`;
`replace_from` is the column from which an accepted completion replaces text.
`slash.exec {session_id,command:"/status",profile?}` or
`command.dispatch {session_id,name:"status",arg:"",profile?}` returns a directive.

Directive `exec|plugin` renders `output`; `skill|send` requires a **new durable
prompt.submit** of returned `message` (display `display` when supplied);
`prefill` edits composer only; `alias` resolves target. Never both submit the
original command and its returned directive.

Sources: `tui_gateway/contracts/tools_commands.py:204`,
`tui_gateway/contracts/tools_commands.py:267`, `tui_gateway/contracts/tools_commands.py:302`,
`tui_gateway/contracts/profiles_vault_complete_foreign_subagents.py:50`,
`gateway/session_commands.py:1`.

Current handler support includes reads (`help,commands,status,context,version,
whoami,usage,insights,profile,diff,memory,kanban,topup,suggestions,bundles,skills`),
settings (`reasoning,voice,approvals,codex-runtime,footer,busy,verbose,yolo,fast,
personality`), workflow (`goal,subgoal,loop,heartbeat,review,refine,debug,curator,
login,autoprune`), prompt rewriting (`plan,learn,init,moa,blueprint,egress`), and
approval shortcuts. Argument restrictions apply; e.g. some skills/memory forms
are read-only, `voice tts` is refused for local client playback, and cron writes
are refused on a viewer's attached connection. Use native lifecycle controls for
new/resume/stop/delete/model rather than guessing slash parity.

Source: `gateway/session_commands.py:21` (newer than its area AGENTS summary).

`model.options {session_id,explicit_only:false,include_unconfigured:false,refresh:false}`
returns `{providers,model,provider}`. Provider rows include `slug,name,models,
authenticated,capabilities,pricing,limit,usage` and advisory fields. Capabilities
per model include `fast,ultrafast,reasoning,can_disable_reasoning`. Respect unknown
pricing/usage; do not fabricate quota gauges or send model provider secrets.

Source: `tui_gateway/contracts/config_free_tier_control.py:449`.

Change model with `session.mutate` operation `model`, payload
`{model,provider?,reasoning?,confirm?}` and both fences. Expensive selection may
return a confirmation guard; show it and retry only with returned confirmation.
Reasoning-only selection uses operation `reasoning`, payload `{effort:"high"}`
or `{effort:null}` to reset to profile. Known effort strings:
`minimal,low,medium,high,xhigh,max,ultra`, plus disabling `none`. The provider may
clamp the requested effort; read back `reasoning_effort` and
`reasoning_effort_wire` separately.

Sources: `hermes_state_mutations.py:11`, `tui_gateway/contracts/canonical.py:81`,
`hermes_constants.py:1073`, `tui_gateway/contracts/canonical_sessions.py:112`.

Change tier with `config.set {session_id,key:"service_tier",value:"priority"}`.
This is session-scoped. Canonical words: `normal`, `priority` (UI label Fast),
`ultrafast`, `auto`, `cold`; aliases include `fast`. Offer static tiers only when
the selected model/provider advertises support. Create can set `service_tier` too.
Do not use global config writes for composer model/effort/tier selection.

Sources: `gateway/session_busy_controls.py:111`, `agent/fast_mode.py:23`,
`tui_gateway/contracts/canonical_projections.py:21`.

## Further native capabilities and implementation boundaries

Native inspectors can use `session.stats`, `session.context_breakdown`,
`session.control.read`, `tools.show`, `subagent.list/tail/steer/interrupt`,
`process.list/stop/kill`, `rollback.session_diff`, `session.export`,
`session.automation`, and connector operations. Build these as optional
capability/error-aware surfaces. Subagent tail is live-only and bounded; queued
steer means accepted, not proved delivered. UI must preserve permission failures
and stale-generation errors.

Sources: `gateway/session_controls.py:173`, `gateway/session_ancillary.py:25`,
`gateway/session_tui_ops.py:1`, `tui_gateway/contracts/canonical.py:207`.

The shared gateway also has owner-scoped skills/MCP reload, background/aside
prompts, profiles, plugins, groups, and configuration APIs. Desktop-specific
terminal/browser/display/audio bridges require native adaptations and must not
be portrayed as implemented merely because they appear in the method registry.
Legacy fallback is deliberately blocked for most session-writing namespaces.
Keep the Python/Pydantic and generated OpenRPC contracts as the upstream schema
source; tolerate additive response fields, reject unsupported request fields.

Sources: `gateway/session_tui_side.py:1`, `gateway/session_controls.py:173`,
`tui_gateway/ws_legacy_fallback.py:1`, `apps/shared/src/gateway-contract.openrpc.json`.

Recommended Swift implementation: a URLSession WebSocket actor for RPC IDs,
heartbeat/reconnect, and server requests; Codable envelopes with flexible JSON
payloads; a main-actor session store keyed by profile and session; durable local
submission identities and per-session replay cursors; separate Keychain credential
store; native attachment pickers/upload progress; explicit approval cards; searchable
server-driven slash palette; model/effort/tier UI with authoritative readback.
Reconcile history by durable `row_id`/`persisted_turn`, not text equality.

## Live endpoint evidence and gaps

Metadata-only checks on 2026-11-05:

| Surface | Evidence | Verdict |
|---|---|---|
| Running Hermes gateway | PID 8137, loopback `127.0.0.1:55263`, matching source SHA/version above. `GET /api/auth/providers` returned 200 JSON. | Local listener reachable; no authenticated chat or inference exercised. |
| Configured private dashboard URL | `https://rafals-mac-mini.tail71fdd0.ts.net:8443`; Tailscale Serve proxies to `127.0.0.1:18481`. No listener on that port; provider bootstrap returned HTTP 502. | Configured tailnet route currently broken. |
| Existing public Cloudflare ingress | `pocket.wyderka.cc` proxies to `localhost:9220`; no listener on that port. HTTPS bootstrap returned URL transport error. | Existing ingress is not a verified usable Hermes endpoint. |

Commands: `lsof -nP -iTCP -sTCP:LISTEN`, sanitized process executable/action inspection,
selected non-secret endpoint fields from local config, `tailscale serve status`,
and status/content-type-only GETs. No tokens, config bodies, browser credentials,
or conversation contents were printed or copied. No listener/route changes made.

Follow-up metadata discovery confirms the current local gateway is already
gated (`auth_required:true`, `auth_providers:["basic"]`). The existing tailnet
8443 route can target its current loopback port without restarting Hermes;
[mobile-connection-plan.md](mobile-connection-plan.md) contains the exact proposal
and normal-user native password sign-in contract. The route repair was not run.

Before real iPhone acceptance, authenticated HTTPS/WSS reachability and
mobile authorization need implementation/verification. TestFlight upload
does not prove connectivity, attachment delivery, command behavior, or approval
handling on a device. Cloud CI should exercise the transport with deterministic
fixtures and validate archive/signing separately from real gateway/device tests.
