# Infinitum Corporation® for Mac, iPhone and iPad

Native apps for every Infinitum product on macOS 14+ and iOS/iPadOS 17+, plus the :\ARCHITECT\™ Safari Web Extension. One SwiftUI shell (`Packages/InfinitumKit`) runs each product; `Product.json` in each app says which one.

| App | Bundle id | Web app | Cumulus ID client | Sign-in | Amplitude |
|---|---|---|---|---|---|
| SCALVS.ai | `app.infinitum.scalvs` | scalvs.app (mirror ru.scalvs.app) | `scalvs` | in app | on |
| METATRON¹⁰⁰™ | `app.infinitum.metatron` | mttrn.app | `metatron` | in app | on |
| :\ARCHITECT\™ + Safari extension | `app.infinitum.architect` | rchtch.app (cndctr.app redirects here) | `architect` | system sheet | on |
| FabriC++™ | `app.infinitum.fabric` | infinitumfabric.app | `fabric` | in app | on |
| $FIRM Wallet™ | `app.infinitum.firm-wallet` | firmwallet.app | `firm-wallet` | in app | on |
| $Firmament Network™ | `app.infinitum.firmament` | firmnetwork.app | `firmament` | in app | on |
| VEIL</>™ | `app.infinitum.veil` | infinitumveil.app | `veil` | in app | **off** (privacy guarantee) |
| VEIL</>™ VPN | `app.infinitum.veil-vpn` | infinitumveilvpn.app | `veil-vpn` | in app | **off** (privacy guarantee) |

Cumulus://Mail, Drive, ID and Exchange already have a full native Apple app: `infinitum-nexus/apps/cumulus-apple`. It isn't repeated here.

## Sign in with Cumulus ID

Every app opens on a sign-in screen with **Sign in with Cumulus ID** and **Create a Cumulus ID**. There is no app passcode, PIN or password. Both use OAuth 2.0 authorization code + PKCE (S256) against `id.cumuluscloud.app`, and a new Cumulus ID comes straight back to the app signed in.

- **In app** (embedded): Cumulus ID's own pages open in a sheet. Cumulus ID redirects to the product's origin with `?code&state`; the app catches that redirect before it loads and trades the code at `/api/id/token` with the verifier, which never leaves the app. This works with the origins Cumulus ID already accepts (`infinitum-nexus/packages/cid/src/id-clients.ts`), with no server change.
- **System sheet** (`ASWebAuthenticationSession`): used when the product hosts a return page that bounces the code to the app's scheme. `rchtch.app/cid-return?to=desktop` opens `architect://cid`. To move another product to the system sheet, publish the same return page on its origin and set `signIn: "system"` in `scripts/generate.py`.
- **Russia without a VPN:** the app tries `id.cumuluscloud.app`, then `ru.id.cumuluscloud.app`. If the product origin can't be reached, it loads the listed mirror (ru.scalvs.app for SCALVS).
- **One sign-in:** the session is kept in the Keychain and handed to the web app on its own hosts, in `sessionStorage["cumulus-id:<client>"]`, the key the shared Cumulus ID button reads (and `#cid_handoff` for the Podium). The web app's own Sign in, Create and Sign out buttons are routed to the native flow.

## Analytics

Commercial apps link the official Amplitude-Swift **1.20.0** (SwiftPM, pinned) and track page views and sessions only, in the US region. Off: form and text autocapture, session replay, remote config, diagnostics, IP address, city, DMA, carrier and IDFV. No user id is set, and page views carry the domain and path only, never the query or fragment. The VEIL apps don't track.

The key is the **public** API key, supplied at build time: set the repo variable `AMPLITUDE_API_KEY` (Settings → Secrets and variables → Actions → Variables). Without it the apps build with analytics off. The secret key never goes in an app.

## :\ARCHITECT\ for Safari

`Extensions/Architect/Resources` is the Chrome extension from `InfinitumCorp/architect`, adapted for Safari by `scripts/port_architect_extension.py`:

- the side panel becomes the toolbar popup;
- the Chrome-only `sidePanel` and `identity` permissions are dropped, and `tabs` is added;
- `safari-shim.js` loads first everywhere. Sign-in runs in the background, because Safari closes the popup when the sign-in tab opens. The background opens Cumulus ID in a tab and reads the code when the tab reaches `https://rchtch.app/cid-return`.

The extension ships inside the :\ARCHITECT\ app for Mac and iPhone/iPad. On the Mac, the app's account menu has **Turn On the Safari Extension…**.

VEIL</> and VEIL</> VPN have no Safari extension: both are built on `chrome.proxy`, which Safari doesn't offer. On Apple devices, VEIL VPN runs through the system VPN (IKEv2/WireGuard profiles from its site). A native packet-tunnel app needs the Network Extension entitlement after Apple Developer enrollment.

## Build

On a Mac with Xcode 16.3+ and `brew install xcodegen`:

```bash
xcodegen generate
open Infinitum.xcodeproj
```

To add or change a product, edit `PRODUCTS` in `scripts/generate.py` (Python 3 + Pillow), run it, and commit the generated `Apps/` and `project.yml`. To refresh the Safari extension from upstream:

```bash
git clone --depth 1 https://github.com/InfinitumCorp/architect.git ../architect
python3 scripts/port_architect_extension.py ../architect
python3 scripts/generate.py
```

CI (`.github/workflows/apple.yml`, macOS runner, free because the repo is public) runs the InfinitumKit tests and builds every app for macOS and the iOS Simulator. The macOS apps are ad-hoc signed and uploaded as the `infinitum-macos-apps` artifact. To run one, unzip it, then Control-click the app and choose **Open**. For the Safari extension, turn on Safari → Develop → **Allow Unsigned Extensions**.

## Not done yet (needs the Apple Developer account)

Enrollment 475CBWUN28 is pending. Once it is approved:

1. Set `DEVELOPMENT_TEAM` in `project.yml` (via `scripts/generate.py`). Register the bundle ids above, including `app.infinitum.architect.safari`.
2. Add signing as GitHub secrets (certificate + App Store Connect API key) and a release job for TestFlight / notarized Mac builds. Nothing is uploaded today.
3. Optional: Associated Domains, so every product can use the system sheet with an https callback.
