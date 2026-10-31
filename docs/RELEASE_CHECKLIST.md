# Zajel — Android release checklist

Nothing below is ticked yet. Items marked **you** need something only you have (a phone, a keystore, an account).

## Before building

- [ ] **you** Run the manual tests in `docs/TESTING.md` for phases 0–3 and 5 on real phones, and record the
      numbers in `docs/BENCHMARKS.md`.
- [ ] **you** Create an upload keystore and a `android/key.properties` (never commit either). The release build
      currently signs with the debug key, which Google Play rejects:
      `signingConfig = signingConfigs.getByName("debug")` in `android/app/build.gradle.kts`.
- [ ] Decide the final application id. It is `com.zajel.zajel` now; it cannot change after publishing.
- [ ] Set `version:` in `pubspec.yaml` (build number must rise with each upload).
- [ ] Replace the launcher icon (`android/app/src/main/res/mipmap-*`) and the app label.
- [ ] Host `docs/PRIVACY_POLICY.md` at a public URL and fill in its contact address.

## Build

```bash
flutter build apk --split-per-abi --release
flutter build appbundle --release
```

Play wants the `.aab`. The split APKs are for direct installs and testing.

## Automated checks (run before every release)

```bash
flutter analyze
flutter test
```

`test/security_audit_test.dart` fails the build if the manifest, dependencies or code break a hard rule
(cleartext traffic, FileProvider, tracking packages, outside URLs, certificate checks, plain HTTP outside the
browser share, permission list).

## Security checklist (SPEC.md, phase 5)

- [x] No exported FileProvider, no `grantUriPermissions` (audit test).
- [x] `usesCleartextTraffic` is false (audit test). Only the browser share serves HTTP, and says so.
- [x] TLS on every transfer, certificate fingerprint pinned by senders (audit test, integration tests).
- [x] Path traversal: received names are rejected or confined to the download folder (unit + integration tests).
- [x] PIN lockout after 5 wrong attempts for 60 s (integration tests).
- [x] Logs redact tokens, PINs and session ids and export only to a place the user picks (unit tests).
- [ ] **you** Check the merged manifest of the release build:
      `build/app/intermediates/merged_manifests/release/.../AndroidManifest.xml`.
- [ ] **you** Release APK installs and runs on Android 8 and on the newest Android you have.

## Known gaps to decide on

- **Received files on Android** go to the app's own folder (`Android/data/...`), which users cannot open easily and
  which is removed on uninstall. A public Downloads folder needs MediaStore, and the Kotlin data server writes
  with a file path, so it would have to change to write through a file descriptor.
- **Release build uses R8/minify defaults.** Not yet tried on a device. If `mobile_scanner` or the Kotlin servers
  misbehave in release only, check the shrinker rules first.
- **Resume survives a dropped connection, not an app restart.** The session is in memory.
- **LocalSend interop is not tested.** The official apps have never talked to this build.
- **Notifications:** the permission is requested at the first transfer on Android 13+; transfers work without it.
- **Wi-Fi Direct on Android 8 and 9** needs the system accept dialog on the receiver.
- **Play policy:** the foreground service type, camera and location/nearby declarations must be filled in
  Play Console (`docs/PLAY_LISTING.md`).

## Release tests with real testers (SPEC.md)

- [ ] **you** 10 testers on at least 6 phone brands. Record brand, Android version, result, speed.

## Release build facts (31 Oct 2026)

- `flutter build apk --split-per-abi --release` builds: arm64-v8a 26.8 MB, armeabi-v7a 23.1 MB, x86_64 29.0 MB.
  These were measured with the first scanner library, before it was replaced (see below), so re-measure.
  The build sometimes fails once on Windows with a locked CMake metadata file; running it again works.
- The only exported component besides the launcher activity is AndroidX's `ProfileInstallReceiver`, which is
  protected by the `DUMP` permission.
- **Scanner library:** the first QR scanner (`mobile_scanner`) pulled in Google ML Kit and the data-transport
  library, which report usage to Google. That breaks "no analytics, no network calls", so it was replaced with a
  ZXing-based scanner (`qr_code_scanner_plus`). `test/security_audit_test.dart` now reads every plugin's Android
  Gradle file and fails on ML Kit, Firebase or data-transport dependencies. Re-check the merged manifest of each
  release for any `mlkit`, `datatransport` or `firebase` entry.
