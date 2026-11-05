# Release status

Updated 2026-11-05. This file records observed states, not intended configuration.

| Item | Observed state |
| --- | --- |
| GitHub repository | Private [`wydrox/hocket`](https://github.com/wydrox/hocket) created |
| Apple bundle identity | Registered `com.wydrox.hocket`, identifier `3V6VXDQ827`, team `7S3F9767BM` |
| App Store Connect app record | Created via Helium: `6831068473`, store name `hocket: Hermes Agent` |
| Xcode Cloud product/workflow | Onboarding in progress in Xcode; not yet active |
| Cloud toolchain | ASC API lists Xcode 27.2, build 27B52 |
| Xcode local onboarding | System setup completed; saved developer account accessible |
| Local compile/test | NOT_RUN: cloud-only validation requested |
| Cloud compile/test | Run `42000749005`: app compiled and 18 unit tests passed; 3 UI tests failed on inaccessible selectors and unsigned simulator Keychain. Corrections await next cloud run. |
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

## Apple onboarding

The authenticated Helium RAFAL profile created the App Store Connect record.
Apple rejected the bare names `Hermes Pocket` and `hocket` as already used;
the accepted store name is `hocket: Hermes Agent`, with device display name `hocket`.
The public API still cannot create the initial Xcode Cloud product; native Xcode
onboarding is in progress. No signed archive or TestFlight build exists yet.
