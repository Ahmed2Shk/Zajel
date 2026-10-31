# Zajel — Manual test checklist

Use two real Android phones (call them A and B). At least one must support 5 GHz. Emulators cannot test Wi-Fi Direct or hotspots.

Before each phase sign-off, tick every item for that phase and earlier ones.

## Every phase (regression)

- [ ] App opens in Arabic (RTL) and in English without layout breaks
- [ ] Zajel ↔ official LocalSend: send and receive one file each way
- [ ] SHA-256 of received file matches the original

## Phase 1 — Core engine

- [ ] A finds B on the same Wi-Fi within 5 seconds
- [ ] 1 GB file A → B and B → A
- [ ] 100 small photos in one go
- [ ] Receiver declines → sender sees a clear message
- [ ] Wrong PIN → rejected; correct PIN → accepted
- [ ] File named `../../evil.txt` is saved safely inside the download folder

## Phase 2 — Speed

- [ ] Run iperf3 between A and B to know the raw Wi-Fi ceiling; note it
- [ ] Benchmark 1 GB on 5 GHz: record MB/s (target 20–40)
- [ ] Benchmark 1 GB on 2.4 GHz: record MB/s
- [ ] Transfer continues with screen off for 2 minutes
- [ ] Turn Wi-Fi off mid-transfer, turn it on, transfer resumes without restarting
- [ ] 10 GB transfer: memory stays flat (Android Studio profiler)

## Phase 3 — No router

Turn off Wi-Fi networks and mobile data on both phones.

- [ ] A shows QR, B scans, transfer works
- [ ] B shows QR, A scans, transfer works
- [ ] Wi-Fi Direct connects automatically A ↔ B
- [ ] No device found in 5 seconds → QR suggestion appears
- [ ] Camera permission denied → clear message, retry works
- [ ] Location off (older Android) → clear message
- [ ] Test on at least: one Samsung, one Xiaomi/Redmi, one other brand

## Fixes after the first phone test (check each by hand)

- [ ] Received photos and videos appear in the Gallery, other files in Files > Downloads > Zajel (Android 10+)
- [ ] The receiver opens the receiving screen by itself after tapping Accept; speed, files and Open/Cancel work
- [ ] After a send, the next send starts with nothing selected
- [ ] A device whose app was closed disappears from the list within ~20 s; tapping it before that says "no longer available" (no raw "Connection refused")
- [ ] QR: the code is bigger and scans from ~30 cm; if the join times out, "Join by hand" shows the network and password and the send continues after "Connected"
- [ ] Wi-Fi Direct: receiver turns on "Visible", sender searches (~15 s) and finds it. If not, capture `adb logcat -s ZajelWifi` from both phones: it shows whether `discoverPeers`, `discoverServices` and the service callback fired (this was not testable without two phones, so treat it as unverified until you do)
- [ ] Speed test: on failure the screen shows the reason; 64 MB is the default size
- [ ] Transfer screens show the Wi-Fi band and link speed; below 3 MB/s on a big transfer a hint suggests QR / Wi-Fi Direct
- [ ] Browser share text explains that nothing goes through the internet

## Phase 4 — Desktop and browser

- [ ] Windows ↔ Android both ways
- [ ] Linux or macOS ↔ Android both ways
- [ ] Laptop joins the phone hotspot using the QR details
- [ ] Browser: open QR URL on another phone, download a file
- [ ] Browser: upload a file to the phone

## Phase 5 — Release

- [ ] No exported FileProvider (check merged AndroidManifest)
- [ ] `usesCleartextTraffic` is false
- [ ] PIN lockout after 5 wrong attempts
- [ ] Logs export works offline
- [ ] Release APK installs and runs on Android 8 and on the newest Android available
- [ ] 10 testers, 6+ brands, results recorded

## Phase 6 — iPhone

- [ ] iPhone scans Android QR, joins hotspot, receives a file
- [ ] iPhone sends a file to Android
- [ ] Local Network permission denied → clear message
- [ ] Wi-Fi Aware experiment: record what worked and what did not
- [ ] TestFlight build installs from the cloud pipeline

## Benchmark log

| Date | Phase | Phones | Band | File | MB/s | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |
