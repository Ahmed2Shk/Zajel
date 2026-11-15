# Zajel — Code audit (commit 69d48fe, 2026-11-15)

Static review of the whole repo: Dart (`lib/`), Kotlin (`android/app/src/main/kotlin`), manifest, Gradle.
**Not run:** `flutter analyze`, `flutter test`, or anything on a phone (the review environment had no Flutter SDK).
Each finding is marked **[confirmed]** (follows directly from the code) or **[plausible]** (needs a device test).

Fix in the order of the IDs inside each group. After each group run `flutter analyze` and `flutter test`,
add a regression test where one is named, and keep LocalSend interop working (CLAUDE.md).

## A. Transfer correctness

### A1. Two sends can run at once and corrupt each other [confirmed]
- `lib/core/transfer/transfer_providers.dart:158-372` — `SendJobNotifier` keeps one `_cancelled` flag and one `_session`
  for every send. `send()`/`sendVia()` reset `_cancelled = false` without checking that an earlier send has ended.
- `lib/features/send/transfer_progress_screen.dart` has no `PopScope`: Back returns to the radar while the transfer
  keeps running with no screen. Tapping a device again starts a second send on the same notifier.
- Also after Cancel: the old `send()` is still unwinding; a new send resets `_cancelled`, so the old one writes
  `failed` into the new job's state and its `finally` calls `release(endpoint)`, which leaves the hotspot the new
  transfer is using.
- Fix: give each send its own token object (`final run = Object(); _current = run;` and check `identical(_current, run)`
  before every state write and in `isCancelled`). Refuse to start while a send is active. Add `PopScope(canPop: false)`
  on the progress screen while status is `connecting`/`sending` (Back asks "cancel the transfer?").
- Test: start send A, cancel, start send B immediately; A's late failure must not change B's state or release B's endpoint.

### A2. Closing the activity kills the transfer and leaves a zombie foreground service [confirmed]
- The Flutter engine (and so the whole transfer) lives in `MainActivity`. Back on the home screen, or swiping the app
  from recents, destroys it. `MainActivity.onDestroy` (`MainActivity.kt:87-96`) stops the data server and transports
  but never stops `TransferService`, which then keeps the notification, the Wi-Fi lock and a 4-hour wake lock.
- Fix (minimum): in `onDestroy` call `stopService(Intent(this, TransferService::class.java))`; override
  `onTaskRemoved` in the service to `stopSelf()`; while a transfer is active, make Back on the root route call
  `moveTaskToBack(true)` instead of finishing. Fix (proper, later): host the engine in the service so transfers
  survive the activity.

### A3. A broken transfer blocks the receiver for up to 2 minutes (HTTP 409) [confirmed]
- `receive_server.dart:356,368` refuse any new `prepare-upload` while `_session != null`; a sender that vanished
  without `/cancel` holds the slot until `sessionIdleTimeout` (2 min, line 180). The sender shows the raw text
  "Blocked by another session".
- Fix: if the new request comes from the same sender (same fingerprint in `info`, or same IP) and the current session
  has had no data for ~10 s, abort the old session and continue. Map 409 to a localized "receiver is busy" message.

### A4. One odd file name fails the whole batch [confirmed]
- `receive_server.dart:352-355` runs `sanitizeReceivedFileName` on every file and throws for the whole request.
  `file_name_sanitizer.dart:21-41` rejects leading/trailing spaces and a trailing dot in any segment.
- Fix: on the sender, normalize names before `prepare-upload` (trim segments, strip trailing dots, replace control
  characters). On the receiver keep the strict check but drop only the offending file from the accepted set
  (it gets no token) instead of answering 400.

### A5. The Apps tab sends broken APKs for most Play Store apps [confirmed]
- `MainActivity.kt:282-302` returns only `applicationInfo.sourceDir` (base.apk). Apps installed as bundles also have
  `splitSourceDirs`; base.apk alone does not install or crashes.
- Fix: return the splits too. Either send them as `Name/base.apk`, `Name/split_*.apk` (and say on the receiver that
  a split installer is needed), or hide/mark apps that have splits. Do not present them as a single installable APK.

### A6. Receiving only works while the app is open on screen [confirmed]
- The accept dialog (`incoming_transfer_host.dart`) is the only signal; there is no notification, and
  `_askUser` (`localsend_service.dart:332-343`) declines after 60 s. The foreground service starts only after accept.
- Fix: post a high-priority notification (with Accept/Decline actions) for an incoming request when the app is not
  resumed. State clearly in the UI that the receiver must keep the app open.

### A7. A failed service start is silent; the send screen spins forever [confirmed]
- `localSendServiceProvider` (`transfer_providers.dart:25-71`) can throw (port 53317 taken by another app, download
  folder not writable). Every screen reads `.value` and treats null as "not ready"; `send()` awaits `.future` outside
  its try block (line 180), so the job stays `connecting`.
- Fix: show the provider's error state on the home screen with a retry; move the `await ...future` inside the try;
  fall back to another port when 53317 is taken.

### A8. No resume across sessions [confirmed, design]
- After the idle timeout or a cancel, `_abortSession` (`receive_server.dart:925-939`) deletes every part file. A big
  transfer that loses the link for more than ~1 minute starts again from zero.
- Fix (later): keep part files plus a small sidecar (size, received ranges) keyed by sender fingerprint + name + size,
  and offer them back through `/zajel/progress` on the next session.

## B. Speed

### B1. Wrong Wi-Fi lock mode [confirmed]
- `TransferService.kt:81-106` takes `WIFI_MODE_FULL_LOW_LATENCY` on API 29+, with a comment saying it works with the
  screen off. AOSP documents the opposite: low-latency is active only with the screen on and the app in the
  foreground (and "throughput may be reduced"); `WIFI_MODE_FULL_HIGH_PERF` is the one that stays active with the
  screen off or in the background.
- Fix: acquire `WIFI_MODE_FULL_HIGH_PERF` (keep it on every API level; on API 34+ the system maps it itself).
  Measure the router path again afterwards.

### B2. The send path runs in Dart on the UI isolate [confirmed]
- `send_client.dart:211-504`: file read, HTTP and TLS for all four connections run on the main isolate, against the
  rule in CLAUDE.md ("never copy file bytes through Dart"). It caps the sender and janks the UI.
- Fix: a Kotlin sender behind Pigeon (HttpsURLConnection or OkHttp with the pinned fingerprint, `FileChannel` reads,
  4 threads), mirroring `NativeDataServer`. Interim: run `SendClient.upload` in a background isolate.

### B3. Every received file is written twice [confirmed]
- `MainActivity.kt:204-241` copies each finished file into MediaStore and deletes the private copy
  (`receive_tracker.dart:198-238`). Doubles disk I/O and needs twice the free space for the largest file.
- Fix: on API 30+ create the destination directly in the public folder (`Download/Zajel`, `Pictures/Zajel`, ...)
  by file path, let `NativeDataServer` write there, then `MediaScannerConnection.scanFile`. Keep the copy only for API 29.

### B4. A synchronous, fsync'd log line per chunk on the UI isolate [confirmed; size of effect estimated]
- `receive_server.dart:635-637` logs every committed chunk; `app_log.dart:39-51` writes with
  `writeAsStringSync(..., flush: true)`. Medium files travel as 1 MB pieces, so a photo batch causes tens of blocking
  fsyncs per second, and each chunk's HTTP answer waits for it.
- Fix: remove the per-chunk note (or log once per file); make `AppLog` buffer and flush asynchronously.

### B5. `SO_RCVBUF` set after accept disables TCP autotuning [confirmed in code; effect plausible]
- `NativeDataServer.kt:133` `receiveBufferSize = 1 MB`. On Linux this locks the buffer (and can shrink it below the
  system's Wi-Fi default), which limits throughput on higher-latency paths such as two phones behind one router.
- Fix: delete that line.

### B6. SHA-256 computed for every byte on the Dart path, even with nothing to compare [confirmed]
- `receive_server.dart:530-544` and `844-852` hash always; the result is used only if the sender sent `sha256`
  (Zajel never does, LocalSend usually does not). Slows receiving from official LocalSend apps.
- Fix: create the hasher only when `file.meta.sha256 != null`.

### B7. Files are sent one after another [confirmed]
- `send_client.dart:248-274`: only pieces of one file run in parallel. Files of 256 KB–1 MB go as single requests in
  sequence, and every chunked file first costs a `GET /zajel/progress` round trip (line 357) even on the first attempt.
- Fix: one shared queue of pieces across all files; skip the progress request on the first attempt of a session.

### B8. `prepare-upload` does heavy work per file before answering [confirmed]
- `receive_server.dart:398-415` creates and truncates a part file and makes a platform call for every accepted file,
  including the small ones that later travel inside the tar. Thousands of photos delay the first byte by seconds.
- Fix: reserve and register lazily (on the first chunk of a file), or batch the registration in one platform call.

### B9. Unthrottled progress events on the Dart receive path [confirmed]
- `receive_server.dart:536-543` emits `FileProgress` per socket read; `receive_tracker.dart:161-177` rebuilds the whole
  file list for each (O(files) per event). Throttle to ~10 per second per session, as the native path already does.

### B10. Smaller items
- `transfer_providers.dart:299-307`: every radar send first asks `/zajel/direct` (up to 6 s when the peer is slow).
  Cache the "no hotspot" answer per device, lower the timeout to ~1.5 s.
- `localsend_service.dart:165,370-379`: announce every 8 s also during a transfer; each announce makes every peer
  open a TLS connection to `/register`. Pause while `_activeTransfers > 0`.
- `NativeDataServer.kt:189-200`: one `pwrite` per TLS record (≤16 KB). Fill the 256 KB buffer before writing.
- `transfer_providers.dart:222-226`: the speed shown is the average since the start, so it lags; use a 3 s window
  as the receiver does.

### The router path (0.2–2 MB/s in `docs/BENCHMARKS.md`)
Not explained by the code alone. Before blaming the router, test the same two phones on the same router with the
official LocalSend app (or iperf3). If that is fast, B1, B5 and B2 are the suspects, in that order.

## C. File picker and selection

### C1. A failed or cancelled send throws the selection away [confirmed]
- `home_screen.dart:84-88` clears the selection on every tap of Send. After a failure the only button is OK → home
  (`transfer_progress_screen.dart:352-356`), so the user must pick everything again.
- Fix: add "Try again" and "Choose another device" on the failed state (keeping the selection); clear only after a
  successful send or an explicit "clear".

### C2. The Files tab copies every picked file into the cache first [confirmed in file_picker 13.3.0 source]
- `file_picker_screen.dart:54-60` uses `FilePicker.pickFiles()`. On Android the plugin copies each file to
  `cacheDir/file_picker/<stamp>/` with an 8 KB buffer and fsync before returning: a long silent wait for big files,
  double storage, and a file whose copy fails is dropped without a message. The copies are never deleted
  (`clearTemporaryFiles` is never called), and picking the same file twice adds it twice (new path each time).
- Fix: replace with a native picker behind Pigeon (`ACTION_OPEN_DOCUMENT`, multiple, persistable read permission) and
  send from the content Uri (`ParcelFileDescriptor`) without copying. Interim: show a "preparing files" state, call
  `clearTemporaryFiles()` after a send and at start-up, de-duplicate by name + size.

### C3. Media tiles give no feedback while a tap is being resolved; double tap adds the file twice [confirmed]
- `media_grid.dart:90-109`: `resolve()` can take long (it may copy the file); the tile stays unselected, a second tap
  appends a second entry with the same id. `ref` is also used after the awaits without a `mounted` check.
- Fix: keep a `_pending` set of ids, show a spinner on the tile, ignore taps while pending, check `mounted`, and make
  `SelectedFilesNotifier` expose `add`/`remove` that de-duplicate by id.

### C4. `_addPaths` can lose updates [confirmed, rare]
- `file_picker_screen.dart:37-52` reads the list, awaits, then overwrites it. Use the notifier's `add` from C3.

### C5. The selection lives only in memory [confirmed]
- If Android kills the app while the system picker or a permission dialog is open (common on low-RAM phones), the
  selection is gone; the plugin's `retrieveLostData` is never called.
- Fix: persist the selected paths/ids (shared_preferences) and restore them on start; call `retrieveLostData`.

### C6. Navigation
- `qr_scan_screen.dart:52-57`: scanning with nothing selected replaces the scanner with the picker; the picker's Send
  then opens the radar, not the scanner. Remember the scanned code and continue with it after picking.
- `done_screen.dart:88-92` and `transfer_progress_screen.dart:132`: `context.go()` to a top-level route leaves a
  one-page stack, so Back closes the app. Use `go(home)` then `push(...)`, or nest the routes under `/`.
- `file_picker_screen.dart:180-205`: the Files tab lists everything selected in every tab.

## D. Security and release

- D1 [confirmed] `android/app/build.gradle.kts:34-40`: release is signed with the debug key. Create a release
  keystore (outside git), `key.properties`, and enable `isMinifyEnabled`/`isShrinkResources`.
- D2 [confirmed] `AndroidManifest.xml`: `android:allowBackup` is not set (defaults to true), so the device's private
  key (`zajel_key.pem`) can leave the phone in a backup. Set `allowBackup="false"` (or exclude the key).
  Also `android:label="zajel"`: use a string resource ("زاجل" / "Zajel").
- D3 [confirmed] `receive_server.dart:895-902`: `/zajel/direct` gives the hotspot name, password, pairing token and
  PIN to any device on the Wi-Fi that asks. The accept dialog still protects the files, but the PIN no longer does.
  Return only what is needed to join (ssid, pass, ip, port, fingerprint) and require the PIN or Accept as usual.
- D4 [confirmed] `receive_server.dart:1009-1014`: request bodies are read without a size limit; file sizes are not
  checked against free space. Cap JSON bodies (e.g. 8 MB) and refuse transfers larger than the free space.
- D5 [confirmed] `qr_host.dart:67`: 4-digit pairing PIN with a per-IP lockout. Use 6 digits.
- D6 [confirmed] `README.md` is the Flutter template; `docs/TRANSPORTS.md` still describes QR format v1 while the
  code is v2 (`pairing_payload.dart:33`).

## E. Other

- E1 [confirmed] Discovery is multicast only. CLAUDE.md promises mDNS in parallel; it is not implemented, and there is
  no fallback scan. Many access points drop multicast between clients, which shows as an empty radar.
- E2 [plausible] `multicast_discovery.dart:106-117` sends on the default interface only. With mobile data on and a
  Wi-Fi that has no internet, the announcement may leave through the wrong interface. Send once per interface.
- E3 [confirmed] `send_client.dart:31-36`: file dates are not sent (`metadata.modified`) and never applied on the
  receiver, so received videos and documents get today's date.
- E4 [confirmed] `MainActivity.kt:282-302`: `listInstalledApps` runs on the Android main thread. Make it `@async` on a
  background executor.
- E5 [confirmed] `WifiTransport.kt:229-253` (Android 8/9): the added network is never removed and the user's Wi-Fi is
  not restored after `leaveNetwork`.
- E6 [confirmed] `WifiTransport.kt:135-137`: `onStopped` of the hotspot is not reported to Dart; the QR screen keeps
  showing a dead network.
- E7 [confirmed] Changing a setting restarts the service (`transfer_providers.dart:29-37,69`), which aborts a running
  transfer; the old service's `nativeData.stop()` can also stop the new native server. Do not restart while a
  transfer is active, and make stop/start sequential.
- E8 [confirmed] `settings_screen.dart` has no length limit on the device name; `pairing_payload.dart:119` rejects a
  name over 64 characters, so that device's QR code never scans. Limit the name to 40 characters.
- E9 [confirmed] `transfer_progress_screen.dart:213` shows raw English exception text. Map known errors to ARB strings.
- E10 [confirmed] Android 8/9: received files stay in the app's private folder (`MainActivity.kt:205`).
