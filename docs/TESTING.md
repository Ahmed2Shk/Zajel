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
