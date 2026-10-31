# Zajel (زاجل)

Offline, ad-free file transfer app. Faster and simpler than SHAREit, and wire-compatible with the LocalSend v2.1 protocol: https://github.com/localsend/protocol

Read `docs/SPEC.md` before every phase. The phase you are working on is listed in `docs/PROMPTS.md`. Do not start work from a later phase.

## Platform order

1. Android (phases 0–3 and 5)
2. Desktop (Windows, macOS, Linux) and browser (phase 4)
3. iOS last (phase 6). Keep the `ios/` folder compiling-ready, but do not add iOS code before phase 6. The developer has no Mac; iOS builds go through Codemagic or GitHub Actions macOS runners.

## Architecture

Feature-first Flutter app. Riverpod 3, go_router, freezed.

```
lib/
  core/
    discovery/   UDP multicast 224.0.0.167:53317 + mDNS, in parallel
    transport/   TransportManager: Wi-Fi Direct > LocalOnlyHotspot via QR > same LAN (Wi-Fi Aware later)
    transfer/    LocalSend v2 HTTP(S) server + client, chunking, resume
    security/    self-signed TLS cert per device, SHA-256 fingerprint, optional PIN
  features/
    send/ receive/ qr/ history/ settings/
android/app/src/main/kotlin/...   native transport + data path
```

- Native platform code is exposed to Dart through **Pigeon** only. No raw MethodChannel strings.
- On Android the **data path is native Kotlin**: socket receive and disk write use FileChannel and direct ByteBuffers. Dart controls the session and shows progress. Never copy file bytes through Dart.
- Never load a whole file into memory.

## Hard rules

- Every phase must keep interop with the official LocalSend apps working. Test against them.
- All transfers use TLS. No cleartext traffic, except the optional browser page in phase 4, which must warn the user.
- Sanitize every received file name: reject `..`, absolute paths and control characters.
- No exported FileProvider. No `grantUriPermissions` on exported components.
- No ads, no analytics, no network calls to any server. The app works fully offline.
- UI is Arabic-first (RTL) with English. All user-facing strings go through ARB files.
- Design tokens live in `docs/design/README.md`. Use them through ThemeData, never hardcoded colors.

## Workflow

- Before coding a phase: restate its acceptance criteria from `docs/SPEC.md`, then propose a short plan.
- After coding: run `flutter analyze` and `flutter test`, then list what I must test by hand from `docs/TESTING.md`.
- Keep commits small, one logical change each, with clear messages.
- If something in the spec is impossible on a given Android version or device, say so plainly and propose the closest alternative. Do not fake it.

## Commands

```
flutter pub get
flutter analyze
flutter test
flutter run            # on a connected Android phone
flutter build apk --split-per-abi --release
```
