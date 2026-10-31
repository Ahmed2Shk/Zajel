# Zajel — Specification

## Product

Zajel moves files between nearby devices with no internet, no account and no ads. It must be as fast as SHAREit's turbo mode on modern phones, and simpler to use.

### In scope

- Send and receive any file type: photos, videos, apps (APK), documents, whole folders.
- Automatic discovery of nearby devices.
- QR pairing on every device ("Show QR" / "Scan QR"), as a first-class option next to discovery.
- Transfers with no router: Wi-Fi Direct and LocalOnlyHotspot.
- Interop with the official LocalSend apps (Android, Windows, macOS, Linux, iOS).
- Browser send/receive for devices without the app.
- Resume after a dropped connection.
- Arabic (RTL) and English.
- Transfer history.

### Out of scope

- Accounts, login, cloud, internet transfers.
- Ads, analytics, tracking of any kind.
- Chat or social features.
- Bluetooth-only transfers (too slow; Bluetooth/BLE may be used for discovery only).

## Performance targets

| Metric | Target |
| --- | --- |
| Throughput, two modern Android phones on 5 GHz | 20–40 MB/s sustained on a 1 GB file |
| Throughput, older 2.4 GHz devices | best effort, expected 5–10 MB/s |
| Time from tapping a device (or scanning QR) to first byte | under 5 seconds |
| Successful transfers in the test matrix | at least 95% |
| Memory during a 10 GB transfer | flat; no growth with file size |
| Transfer continues with screen off | yes, via foreground service |

## Security

- TLS 1.3 on every transfer, self-signed cert per device, identity = SHA-256 fingerprint.
- QR carries SSID, password, IP, port, cert fingerprint and a one-time session token; the client verifies the fingerprint.
- Optional PIN; lock out after 5 wrong attempts for 60 seconds.
- Receiver always confirms an incoming transfer (unless the sender is a trusted device the user marked).
- Received names sanitized; files only ever written inside the chosen download folder.

## Supported platforms

| Platform | Minimum | Phase |
| --- | --- | --- |
| Android | Android 8.0 (API 26) | 0–3, 5 |
| Windows, macOS, Linux | current Flutter desktop support | 4 |
| Browser | any modern mobile or desktop browser | 4 |
| iOS | iOS 16 (Wi-Fi Aware needs iOS 26 and iPhone 12+) | 6 (last) |

## Acceptance criteria per phase

### Phase 0 — Foundation
- Project builds and runs on a real Android phone.
- Folder structure matches CLAUDE.md. Riverpod, go_router, freezed, Pigeon set up.
- Theme built from `docs/design/README.md` tokens. Arabic and English ARB files exist.

### Phase 1 — Core engine
- All LocalSend v2.1 routes implemented: register, info, prepare-upload, upload, cancel.
- Discovery finds the official LocalSend app on the same network, and the official app finds Zajel.
- A 1 GB file transfers in both directions between Zajel and official LocalSend, with matching SHA-256.
- Unit tests for protocol models; integration test for a local 1 GB transfer.

### Phase 2 — Speed
- Android receive and disk write are native Kotlin.
- Parallel chunked upload (3–4 connections, 4–8 MB chunks) and resume.
- Benchmark screen shows MB/s, connection time, CPU.
- 20–40 MB/s between two modern 5 GHz phones; before/after numbers recorded in `docs/BENCHMARKS.md`.

### Phase 3 — No router
- QR pairing works Android ↔ Android with Wi-Fi and mobile data off.
- Wi-Fi Direct works Android ↔ Android automatically.
- If discovery finds nothing in 5 seconds, the app suggests QR.
- Correct permissions and clear messages on Android 8, 10, 12, 13, 14+.

### Phase 4 — Desktop and browser
- Windows, macOS and Linux builds send and receive with Android.
- Browser page on the phone can download and upload files via a QR URL.

### Phase 5 — Android release
- Final UI per the design, Arabic and English.
- Security checklist in TESTING.md passes.
- Release APK/AAB split per ABI; Play Store listing and privacy policy written.
- 10 people tested on at least 6 different phone brands.

### Phase 6 — iPhone (last)
- iPhone joins an Android hotspot by scanning the QR and transfers both ways.
- Wi-Fi Aware experiment behind a feature flag, with logs; works or is documented as not working.
- Cloud build to TestFlight set up without a Mac.
