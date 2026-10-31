# Zajel — Prompts for Claude Code

انسخ برومت المرحلة الحالية بس. ما تنتقل للي بعده قبل ما تخلص قائمة المرحلة بـ `docs/TESTING.md` على جوالين حقيقيين. علّم على المرحلة لما تخلص.

- [ ] Phase 0 — Foundation
- [ ] Phase 1 — Core engine
- [ ] Phase 2 — Speed
- [ ] Phase 3 — No router (QR + Wi-Fi Direct)
- [ ] Phase 4 — Desktop and browser
- [ ] Phase 5 — Android release
- [ ] Phase 6 — iPhone (last)

---

## Phase 0 — Foundation

```text
Read CLAUDE.md, docs/SPEC.md and docs/design/README.md.
Scaffold the Flutter app "zajel" in this folder. Android first; keep the iOS and desktop folders but do not target them yet.
- Set up the folder structure from CLAUDE.md, Riverpod 3, go_router, freezed, Pigeon, flutter_localizations with Arabic and English ARB files.
- Build ThemeData (dark default + light) from the tokens in docs/design/README.md. No hardcoded colors in widgets.
- Empty screens with routes for: home, file picker, discovery, QR show, QR scan, transfer progress, done, settings.
- Do not implement transfer features yet.
Restate the Phase 0 acceptance criteria from SPEC.md first, then do the work, then run flutter analyze and flutter test and tell me how to run it on my phone.
```

## Phase 1 — Core engine

```text
Read CLAUDE.md and the Phase 1 section of docs/SPEC.md. Implement the LocalSend v2.1 protocol in core/transfer and core/discovery:
- POST /api/localsend/v2/register, GET /info, POST /prepare-upload, POST /upload, POST /cancel
- multicast announce (send both "announce" and legacy "announcement" fields)
- HTTPS with the device's self-signed cert; the fingerprint is the SHA-256 of the cert
- receiver accept/decline dialog, optional PIN via ?pin=
- stream file bytes from disk to socket; never load a whole file into memory
- sanitize received file names: reject "..", absolute paths and control characters
Add unit tests for request/response models and an integration test that sends a 1 GB file between two local instances. Then tell me exactly how to test interop with the official LocalSend app.
```

## Phase 2 — Speed

```text
Read CLAUDE.md and the Phase 2 section of docs/SPEC.md. Optimize throughput without breaking LocalSend interop:
- move the Android data path to native Kotlin behind Pigeon: socket receive and disk write happen in Kotlin (FileChannel, direct ByteBuffers, no copies through Dart). Flutter only controls the session and shows progress. LocalSend has a known Android receive slowdown caused by its file-writing library; we must not repeat it.
- split each file into 4–8 MB chunks and upload them over 3–4 parallel connections; write each chunk at its offset with FileChannel.write(buffer, position)
- resume: persist which chunks finished; on reconnect, skip them
- Android: hold WifiLock (WIFI_MODE_FULL_HIGH_PERF) and a partial WakeLock during transfers; run transfers in a foreground service so they survive screen-off and aggressive OEM battery savers
- skip compression for already-compressed media; stream many small files as a tar
- add a benchmark screen: send a 1 GB test file and report MB/s, connection time and CPU usage
Target: 20–40 MB/s between two modern 5 GHz Android phones. Record before/after numbers in docs/BENCHMARKS.md and explain each change in one line.
```

## Phase 3 — No router (QR + Wi-Fi Direct)

```text
Read CLAUDE.md and the Phase 3 section of docs/SPEC.md. Add router-free transfers on Android, in Kotlin behind a Pigeon API:
- QR pairing as a first-class option on every Android device, next to automatic discovery: "Show QR" and "Scan QR" buttons on both the send and receive screens
- the device showing the QR starts a LocalOnlyHotspot (prefer 5 GHz when supported) and encodes SSID, password, IP, port, cert fingerprint and a one-time session token
- the scanning device joins via WifiNetworkSpecifier (Android 10+) or legacy WifiManager below that, verifies the cert fingerprint from the QR, then uses the normal transfer engine; the same QR format is used later by iOS
- Wi-Fi Direct (WifiP2pManager) for automatic Android-to-Android, with group owner on the receiver
- if automatic discovery finds nothing within 5 seconds, suggest the QR option
- handle every permission per Android version: NEARBY_WIFI_DEVICES (13+), CAMERA for scanning, location (older), and clear error messages when Wi-Fi or location is off
- TransportManager tries methods in order and falls back automatically
Test on two real phones with mobile data and Wi-Fi off, both with discovery and with QR.
```

## Phase 4 — Desktop and browser

```text
Read CLAUDE.md and the Phase 4 section of docs/SPEC.md. Extend reach to computers and browsers (still no iOS):
- build the desktop targets (Windows, macOS, Linux) on the same core; on desktop, discovery and transfer run over the LAN or by joining the phone's hotspot via the QR details
- web receive/send: the phone serves a small mobile-friendly HTML page over its local HTTP server; a QR shows the URL so any browser can download or upload; show a warning that the browser page is not encrypted
- test interop with the official LocalSend desktop apps
List what works and what does not on each platform pair after testing.
```

## Phase 5 — Android release

```text
Read CLAUDE.md and the Phase 5 section of docs/SPEC.md. Prepare the Android release:
- UI: match the screens in docs/design/, one-tap Send and Receive, Show QR / Scan QR, live progress with speed and ETA, Arabic (RTL) and English
- security review: no exported FileProvider, no cleartext traffic, TLS everywhere, path-traversal tests, PIN lockout after 5 wrong attempts
- crash and error reporting that works offline (local logs the user can export)
- reduce APK size: split per ABI, remove unused packages
- write the Google Play listing and privacy policy: no ads, no tracking, works offline
Run the full test suite and give me a release checklist.
```

## Phase 6 — iPhone (last)

```text
Read CLAUDE.md and the Phase 6 section of docs/SPEC.md. Add iOS as the final phase, reusing the same core and QR format:
- iOS joins the Android hotspot by scanning the QR and connecting with NEHotspotConfiguration, then verifies the cert fingerprint and uses the normal engine
- add the Local Network permission and Bonjour service entries to Info.plist; handle the permission denial with a clear message
- iOS 26+: experimental Wi-Fi Aware transport with Apple's WiFiAware framework, behind a feature flag; Android side uses WifiAwareManager; log every discovery step
- I do not have a Mac: set up Codemagic (or GitHub Actions macOS runners) to build, sign and upload to TestFlight from the GitHub repo, and write step-by-step setup instructions for me
- prepare the App Store listing
List what works and what does not between Android and iPhone after testing.
```
