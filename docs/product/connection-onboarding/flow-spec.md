# Flow specification

## Before and after

Before: URL, username and password appeared without instructions for obtaining
them. URL validation remained visible after correction. Backend errors could
suggest checking a token even during password login.

After: **Set Up Hermes** opens an optional, three-step guide. **Check Server**
checks public reachability and the supported login mechanism before a password
is sent. Correcting an input clears obsolete sign-in feedback.

## Flow and states

Connection form → optional Set Up Hermes → Prepare Hermes → Connect Your Device
→ Sign In to Hermes → Enter Server Details → Check Server → Sign In → threads.
Close exits at any point; Previous Step permits review. Help and Privacy reopens
the same guide later. Reading help preserves the entered server address.

1. Prepare Hermes: explains server-side execution and prerequisites. Disclosures
   provide real Desktop Settings → Web access / Providers / My own URL / Start
   labels, and separately explain the basic password provider. Existing configured
   servers can continue without changing settings. No fictional pairing button.
2. Connect Your Device: Tailscale/VPN, HTTPS origin and port, Safari reachability,
   and why localhost is not the server address on a phone.
3. Sign In: Check Server, the server’s Username & Password credentials, advanced
   native token entry, Keychain storage and the expected thread-list ending.

Check Server states: empty input (disabled), invalid origin (inline validation),
checking (progress), password available, another provider only, no providers,
network/TLS/proxy error. Editing the address cancels the request and invalidates
its result; late replies cannot describe a different address. Checks do not send
credentials, follow redirects, start conversations, or prove canonical authority.

## Evidence for Hermes instructions

Paths relative to the installed Hermes source checkout:

- `apps/desktop/src/app/settings/index.tsx:376`: Web access navigation.
- `apps/desktop/src/app/settings/web-access-settings.tsx:92`: local native-only.
- `apps/desktop/src/i18n/en_gateway_host.ts:10`: exact labels and restart copy.
- `hermes_cli/webapp_access.py:162`: Nous prerequisite.
- `plugins/dashboard_auth/basic/__init__.py:212`: basic configuration and overrides.
- `hermes_cli/subcommands/config.py:18`: `hermes config edit`.
- `gateway/webapp_listener.py:79`: stable canonical Webapp listener configuration.

These are source-verified labels; the shipped Desktop bundle was not inspected.
The guide says older versions may not include the page. Nous browser sign-in is
not implemented by hocket, and its HTTP-only “This network” address is unsuitable.

## Emotional journey and ethics

Replace uncertainty about credentials with three short tasks. The peak is a real
password-provider discovery result; completion is the authenticated thread list,
not a simulated success screen. Keep compatibility limits beside the relevant
instructions. No tracking, new permission request, credential prefilling or
silent server changes. No business/user conflict identified.
