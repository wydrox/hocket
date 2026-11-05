# Mobile connection plan

Investigation and deployment record, 2026-11-05. The investigation was read-only;
the parent then applied the authorized route repair below. Hermes processes,
credentials, and configuration were preserved.

## Applied repair

The existing tailnet HTTPS :8443 route now proxies to `127.0.0.1:55263`.
Readback verified `/api/auth/providers` returns 200 and unauthenticated
`/api/sessions` returns 401. HTTPS :443 still proxies to T3 at :3773.
Authenticated chat and device acceptance remain unverified. The ephemeral-port
lifetime limitation below still applies.

## Recommendation

Retarget the existing tailnet-only HTTPS route on port 8443 to the already-running
canonical gateway's loopback listener, currently `127.0.0.1:55263`. Keep the current
gateway process and all its sessions. Use the already-configured Hermes `basic`
username/password provider through the native PKCE token exchange described below.
This needs a Tailscale route correction and native sign-in UI, but no new server,
no new auth plugin, and no gateway restart.

The private listener is already authenticated: live `GET /api/status` reports
`auth_required:true`, `auth_providers:["basic"]`; provider discovery reports
`{name:"basic",display_name:"Username & Password",supports_password:true}`.
The configured public hostname matches the existing Tailscale Serve hostname.

## Current sanitized metadata

| Item | Observed metadata |
|---|---|
| Gateway | PID 8137, version 0.22.5; source and running SHA `d49e2ebbaed42718659c13f82c04cde7d8ab10bd`. |
| Canonical listener | `127.0.0.1:55263`; loopback only. Provider bootstrap HTTP 200. |
| Login gate | Enabled; `basic` password provider active. |
| Config | `dashboard.public_url` is `https://rafals-mac-mini.tail71fdd0.ts.net:8443`. |
| Config credential presence | Basic username configured: true; password hash configured: true; signing secret configured: true. Values were neither printed nor copied. |
| Environment-file presence | Basic username override present: true; plaintext password override present: true. Values were neither printed nor copied. Nonempty environment password takes precedence over configured hash. |
| Tailscale Serve | Before repair: :8443 pointed at inactive :18481 and returned 502. After repair: :8443 points at live :55263; auth bootstrap 200, protected sessions 401 without credentials. HTTPS :443 remains T3 at :3773. |
| Public Cloudflare ingress | Existing `pocket.wyderka.cc` points to dead `localhost:9220`; unrelated to this proposal and must remain untouched. |

Evidence commands: listener inventory with `lsof`, endpoint-field-only configuration
inspection, credential-key presence booleans, filtered public auth discovery/status,
`tailscale serve status`, and `tailscale serve --help`. No authenticated session
or model call was made.

## Exact route repair, without restarting Hermes

Before acting, verify the gateway PID still owns port 55263 and the public auth
metadata still says that the gate is enabled with provider `basic`.

```sh
lsof -nP -a -p 8137 -iTCP -sTCP:LISTEN
curl --fail --silent http://127.0.0.1:55263/api/status | python3 -c 'import json,sys; d=json.load(sys.stdin); print({k:d[k] for k in ("auth_required","auth_providers") if k in d})'
tailscale serve status
```

Then the minimal mutation, to be performed separately by the authorized operator:

```sh
tailscale serve --bg --https=8443 http://127.0.0.1:55263
```

This changes the existing 8443 route only. Do not use `tailscale serve reset`,
`tailscale funnel`, or a command targeting default HTTPS 443. The phone must have
Tailscale connected to the same tailnet with access permitted to this machine's
TCP 8443. Tailscale Serve provides the existing valid HTTPS origin; the Hermes
password gate remains the application identity/authorization layer.

Verify without credentials or model traffic:

```sh
tailscale serve status
curl --fail --silent https://rafals-mac-mini.tail71fdd0.ts.net:8443/api/auth/providers | python3 -c 'import json,sys; d=json.load(sys.stdin); print({"providers":[{k:p[k] for k in ("name","supports_password") if k in p} for p in d.get("providers",[])]})'
curl --silent --output /dev/null --write-out '%{http_code}\n' https://rafals-mac-mini.tail71fdd0.ts.net:8443/api/auth/me
```

Expected: existing T3 443 mapping retained; 8443 mapping points to 55263; provider
bootstrap 200 with `basic`; unauthenticated identity endpoint 401. The native app
then verifies authenticated `/api/auth/me`, obtains a WS ticket, and requires
`gateway.ready.payload.session_authority:true` followed by `runtime.describe`.
Do not equate provider bootstrap success with authenticated chat acceptance.

**Lifetime limitation:** 55263 is an ephemeral owner port and can change when the
gateway next restarts. This repair lasts for the current owner. Do not hardcode
the loopback port into the iPhone app; it uses the stable HTTPS origin. Refresh
the proxy target after a future owner restart, or later adopt the fixed-port
configuration below during a user-approved idle restart.

## Native username/password sign-in with existing server support

This is the preferred normal-user setup: HTTPS URL, username, password, Sign in.
The user supplies their existing dashboard credentials. The agent must not fetch
or display local secrets. The app stores issued tokens in Keychain and discards
the password after exchange.

Use a dedicated ephemeral URLSession with its own cookie storage for the sign-in
handshake. Generate a random high-entropy RFC 7636 verifier and random state;
challenge = base64url(SHA256(verifier)), without padding. Choose and retain the
exact callback marker `http://127.0.0.1:53999/cb`. No server actually needs to listen
there for this password-provider flow because the login endpoint returns its
callback in JSON.

1. Request same-origin:

   ```text
   GET /auth/native/authorize?provider=basic&code_challenge=<S256_CHALLENGE>&code_challenge_method=S256&redirect_uri=http%3A%2F%2F127.0.0.1%3A53999%2Fcb&state=<RANDOM_STATE>
   ```

   Expect 302 to same-origin `/login` and a PKCE cookie. Retain that cookie.
   Stop the redirect or allow same-origin `/login`; do not allow an arbitrary
   cross-origin redirect in this native password flow.

2. Send with the same session/cookie jar:

   ```json
   {"provider":"basic","username":"user-entered-name","password":"user-entered-password"}
   ```

   to `POST /auth/password-login`, `Content-Type: application/json`.
   Successful native branch responds:

   ```json
   {"ok":true,"next":"http://127.0.0.1:53999/cb?code=opaque-example&state=original-example-state"}
   ```

3. Parse `next` locally. Require exact callback scheme/host/port/path, no userinfo,
   and exact original state; reject missing/duplicate code or state parameters.
   **Do not request, open, or navigate to that URL.** Extract the one-use code.

4. Exchange on the original HTTPS origin:

   ```text
   POST /auth/native/token
   Content-Type: application/json
   ```

   ```json
   {"code":"opaque-example","code_verifier":"original-verifier"}
   ```

   Response shape:

   ```json
   {"access_token":"opaque-example","refresh_token":"opaque-example","token_type":"Bearer","expires_at":1800000000,"provider":"basic","user_id":"example-user"}
   ```

   Keep access token, refresh token, expiry, provider and origin together in
   Keychain. Clear password, verifier, state and temporary cookies. Avoid all
   request/response-body logging for these endpoints.

5. Authenticate REST with `Authorization: Bearer <access_token>`. `GET /api/auth/me`
   validates identity. `POST /api/auth/ws-ticket` with bearer auth returns
   `{ticket,ttl_seconds:30}`; connect `/api/ws?ticket=<one-use-ticket>`, acquiring a
   fresh ticket on every reconnect. Do not persist ticket URLs in logs.

This exact authorize/password JSON-next/token flow is implemented at
`hermes_cli/dashboard_auth/routes.py:297`, `hermes_cli/dashboard_auth/routes.py:449`,
`hermes_cli/dashboard_auth/routes.py:127`, `hermes_cli/dashboard_auth/routes.py:585`
and exercised by upstream source test
`tests/hermes_cli/test_dashboard_auth_native_flow.py:568`. Tests were inspected,
not run in this read-only investigation. Calling it from a native URLSession and
parsing the JSON callback locally is the proposed client adaptation; it does not
weaken the server's loopback callback allowlist.

The general system-browser OAuth flow still needs a real loopback listener or
future mobile callback support; do not use the password JSON adaptation for an
OAuth provider. The advertised provider's `supports_password` controls this flow.

### Refresh and logout

Refresh before expiry, or once after a structured auth 401:

```text
POST /auth/native/refresh
Content-Type: application/json
```

```json
{"refresh_token":"opaque-example","provider":"basic"}
```

The result has the same fields as native/token. Atomically update the Keychain
pair. Coalesce concurrent refreshes. 401 means sign-in expired/invalid; 503 means
temporary provider failure and should preserve credentials for retry. Do not
refresh-loop on a 403 permission denial.

Logout closes the app's sockets, removes its Keychain tokens/cursors as appropriate,
and clears its temporary cookies. `POST /auth/logout` clears browser cookies and
performs provider best-effort revoke only when a refresh cookie is present; it
does not accept a native refresh token body. The bundled basic provider is
stateless and its `revoke_session` is a no-op, so there is **no per-token native
server revocation** to promise. Existing copied tokens remain valid until expiry;
changing the shared signing secret revokes all basic sessions but is an operator
action with a much broader effect, not an ordinary app sign-out.

Sources: `hermes_cli/dashboard_auth/routes.py:503`,
`hermes_cli/dashboard_auth/routes.py:606`,
`plugins/dashboard_auth/basic/__init__.py:165`.

## Why a new `hermes serve` on 18481 is not the canonical fix

The following is a syntactically supported separate headless backend command:

```sh
hermes serve --host 127.0.0.1 --port 18481 --isolated
```

Existing `dashboard.public_url` and active basic provider would engage its remote
gate, so serving it behind the current :8443 proxy could repair HTTP reachability.
It would not attach the current gateway's session authority to its `/api/ws`.
Standalone `serve` runs the legacy TUI sidecar session runtime. The canonical
authority is injected only by the gateway's `GatewayDashboardMount._bind_state`.
Thus the native client requiring `session_authority:true` should refuse it. It
also creates extra runtime ownership/background services that the direct route
repair avoids. Do not start it for this task.

Sources: `hermes_cli/subcommands/dashboard.py:34`,
`hermes_cli/web_server.py:1384`, `hermes_cli/web_server_app.py:29`,
`gateway/run_api.py:75`, `tui_gateway/ws.py:364`.

## Tailscale identity and later stable-port option

There is no bundled Hermes dashboard-auth provider for trusted Tailscale identity
headers. Tailscale Serve tailnet membership/ACLs narrow who can reach the service;
they do not mint a Hermes Principal. Keep existing basic sign-in. Never trust a
client-supplied identity header or turn off the Hermes gate just because a reverse
proxy connects over loopback.

Read-only source search covered `plugins/dashboard_auth` and
`hermes_cli/dashboard_auth`; existing providers are basic, Nous, self-hosted OIDC
and drain service credentials. `dashboard.trusted_proxies` configures bounded
forwarded proxy metadata, not authentication.

For a later stable canonical port, supported configuration is:

```yaml
webapp:
  enabled: true
  host: 127.0.0.1
  port: 18481
  public_url: https://rafals-mac-mini.tail71fdd0.ts.net:8443
```

Use `hermes config set webapp.enabled true`, `hermes config set webapp.host 127.0.0.1`,
`hermes config set webapp.port 18481`, and
`hermes config set webapp.public_url https://rafals-mac-mini.tail71fdd0.ts.net:8443`
through the supported configuration writer. Existing basic provider remains in
`dashboard.basic_auth`. The Webapp bundle also needs availability; this option
is not an excuse to perform builds on the host during active sessions.
The setting is read at gateway startup; source explicitly requires a gateway
restart to turn Webapp on. At an agreed idle boundary, `hermes gateway restart`
without `--interrupt` would activate it; then repoint :8443 to :18481. This is a
future durable configuration proposal, not required for the current no-restart fix.

Sources: `gateway/webapp_listener.py:1`, `gateway/webapp_listener.py:76`,
`gateway/webapp_listener.py:200`, `gateway/webapp_listener.py:349`.

## Completion evidence still required

After authorized route repair and native implementation: verify auth discovery,
unauthenticated rejection, user-driven login, token refresh, WS canonical ready,
thread list/history, one deliberately user-approved test turn, attachment upload,
approval answering, reconnect replay, and sign-out on a real iPhone. Keep the
Tailscale, auth, canonical transport, model-execution and TestFlight evidence
separate. This plan alone proves none of those runtime acceptance results.
