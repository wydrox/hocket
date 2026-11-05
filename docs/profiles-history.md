# Profiles and paginated conversation history

The profile control at the top of Threads and in Settings opens the same native
profile list. The current selection has a checkmark. Server Default uses the
profile served by the endpoint; named choices use server-provided names and
display labels. Before signing in, an optional profile name can be supplied in
Advanced Connection. An empty value selects the server default.

Selecting a named profile starts a fresh socket and verifies its canonical home
with the read-only `config.get {key:"profile", profile:<name>}` operation. Session
and catalog RPCs then carry that profile name. `runtime.describe`, heartbeat,
capability negotiation and profile discovery remain unscoped; the runtime object
describes the socket's launch authority and must not be relabeled as the selected
profile. Selection never changes Hermes's global default or starts a profile.
Unserved or unauthorized profiles report an error without falling back to another
profile. The last verified preference is stored with the credential in Keychain.

Before switching, hocket saves the current draft and invalidates in-flight work.
Drafts remain keyed by endpoint, account and the verified canonical profile home.
Requests, loading states and errors from the previous scope cannot update the new
scope. A failed switch retains the previously verified saved preference and offers
reconnection.

## History

Active and canonically resumable conversations come from the gateway feeds.
Additional history uses the dashboard's authenticated endpoint:

```text
GET /api/sessions?limit=50&offset=0&order=recent&archived=exclude&exclude_sources=kanban,tool,oneshot,subagent
```

Named connections add `profile=<name>` to HTTP requests, matching gateway routing.
The response contains `sessions`, `total`, `limit`, `offset` and `storage`.
Subsequent pages advance by returned `offset + limit`, because pinned rows can be
backfilled beyond the requested page size. Duplicate pins and compression/reset
lineages are merged while retaining authoritative canonical identity and actual
last activity. An empty terminal page also handles totals that include hidden
rows. There is no fixed 200-conversation client cap.

Load Older Conversations remains reachable when search finds no matches in the
loaded pages. Search is local and does not silently discard previously loaded
pages. Refresh reloads the first page and canonical feeds while retaining older
loaded history; failures preserve rows and allow retrying the same offset.
Account/profile changes reset pagination and reject late replies from the prior
scope. Hidden, archived and internal-source rows are excluded from this list.

History listing does not grant new ownership. Canonical resume can refuse a legacy
conversation or mount an older superseded conversation read-only. Hocket preserves
that server decision; it does not import, duplicate or recreate conversations to
work around it.

## Validation boundary

Regression tests cover routing and canonical profile verification, credential
compatibility, draft isolation, stale async completions, history beyond 200 rows,
backfilled pins, aliases, activity ordering and next-page retries. Native CI result
is recorded separately from a simulator/device walkthrough.

The requested Apple Design / SwiftUI Pro review using simulator screenshots was
explicitly deferred by the user after the sole available iPad simulator remained
held by another session. No simulator screenshots or visual acceptance are claimed
for this change. The planned review covers the profile picker, profile switch,
pagination, no-match search with Load Older, failure/retry, dark appearance and
large Dynamic Type. No review-fixture runtime was added to production code.
