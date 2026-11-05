# Release status

Updated 2026-11-05. This file records observed states, not intended configuration.

| Item | Observed state |
| --- | --- |
| GitHub repository | Private [`wydrox/hocket`](https://github.com/wydrox/hocket) created |
| Apple bundle identity | Registered `com.wydrox.hocket`, identifier `3V6VXDQ827`, team `7S3F9767BM` |
| App Store Connect app record | Created via Helium: `6831068473`, store name `hocket: Hermes Agent` |
| Xcode Cloud product/workflow | Connected: product `6df352ca-bec7-4a8a-b369-a2bb039dc3d9`, workflow `662108ED-715A-440E-B46A-8501DC219743` (`hocket · TestFlight`) |
| Cloud toolchain | ASC API lists Xcode 27.2, build 27B52 |
| Xcode local onboarding | System setup completed; saved developer account accessible |
| Local compile/test | NOT_RUN: cloud-only validation requested |
| Cloud compile/test | Run `42008141296`, attempt 2: 31 unit tests and dark/largest-text UI scenarios passed; one test rejected a fully visible row because of an artificial viewport inset. Corrected commit `8afa9fc2410d5ffc98f67d7c4b4a88e79154dfc3`, run `42011887463`, is pending. |
| Signed archive/upload | NOT_RUN |
| Device/UI/VoiceOver acceptance | NOT_RUN |
| TestFlight | Internal group created, owner enrolled; no build distributed |
| Cloud upload workflow | Xcode Cloud Test and Archive actions configured; internal TestFlight post-action targets `hocket Internal`. GitHub signing fallback prepared but never dispatched. |

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
onboarding initially stopped at GitHub second-factor verification. Repository authorization subsequently completed in Helium. The new product is linked to this exact App Store Connect app and `wydrox/hocket` repository.

The initial default Build 1 used the old `main` commit and was canceled. The replacement workflow has a required Test action on one iPhone 18 Pro with iOS 27.2, an internal-only Archive action, and the `hocket Internal` distribution post-action. It currently starts manually; no scheduled or pull-request triggers are enabled. No signed archive or TestFlight build exists yet.
