# Release status

Updated 2026-11-05. This file records observed states, not intended configuration.

| Item | Observed state |
| --- | --- |
| GitHub repository | Private `wydrox/hermes-pocket` created |
| Apple bundle identity | Registered `com.wydrox.hermespocket`, identifier `G5YVGRJB3Z`, team `7S3F9767BM` |
| App Store Connect app record | Blocked: browser signed out; public API rejects app CREATE |
| Xcode Cloud product/workflow | Not created: first workflow requires Xcode onboarding |
| Cloud toolchain | ASC API lists Xcode 27.2, build 27B52 |
| Xcode local onboarding | Waiting for other system installation tasks |
| Local compile/test | NOT_RUN: cloud-only validation requested |
| Cloud compile/test | Pending source completion and first dispatch |
| Signed archive/upload | NOT_RUN |
| Device/UI/VoiceOver acceptance | NOT_RUN |
| TestFlight | No build distributed |

## Connection deployment

The existing tailnet-only HTTPS route on port 8443 was repaired to point at the
active canonical gateway on loopback port 55263. The separate root HTTPS route
was preserved. After the change, `/api/auth/providers` returned 200 and an
unauthenticated `/api/sessions` request returned 401. No gateway restart or
conversation mutation was performed. The loopback port is ephemeral and needs
route synchronization after a gateway restart; see the deployment plan.

An authenticated credential-broker smoke test timed out before returning a
result. No real Hermes password or token was retrieved or embedded in the app.
Live authenticated chat, model calls, and attachment transfer remain unverified.

## Apple release blocker

Both the shared preview and existing Helium account profile are signed out.
The installed App Store Connect API key can register bundle identifiers and read
the account, but `POST /v1/apps` returns 403: the resource does not allow CREATE.
The public API also cannot create the initial Xcode Cloud product. Initial
account onboarding is still required before an actual TestFlight build can exist.
