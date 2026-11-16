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

## After the full review (check each by hand)

- [ ] QR still works both ways and reaches the old speed (the transfer engine changed: files from 1 MB now go in parallel pieces)
- [ ] A batch of photos (2-6 MB each) over the router: note the speed, compare with before
- [ ] Home > Receive opens the QR waiting screen; a device on the same Wi-Fi can still send without scanning
- [ ] The app no longer asks for the Wi-Fi permission at launch, and no "DIRECT-zj-..." network appears until "Visible" is switched on
- [ ] Wi-Fi Direct: switch "Visible" on (receiver), search (sender), then Settings > export log on BOTH phones. The lines starting with `wifi` say what each phone did: `direct receiver: group created`, `... MHz`, `search: finished, N Zajel receiver(s), M Wi-Fi Direct device(s) in range`
- [ ] Turn Wi-Fi off on the sender right at the end of a transfer, then on again: the sender must end with "done", not "declined"
- [ ] Cancel on the receiver in the middle of a file: that file must not appear in the Gallery or Downloads

## Automatic hotspot (check each by hand)

Both phones on the same Wi-Fi.

- [ ] B taps Receive (QR screen). A picks a file and taps B on the radar: Android asks A to connect to "AndroidShare_...", A accepts, the transfer runs at the QR speed (around 30 MB/s), not the router speed
- [ ] A's exported log has `transport the receiver offers its hotspot: switching to it` and `wifi join: connected to AndroidShare_...`
- [ ] A declines Android's connect dialog: the transfer still starts over the Wi-Fi (slow), with no PIN prompt
- [ ] B is NOT on the Receive screen: tapping B sends over the Wi-Fi as before
- [ ] Wi-Fi off on both phones, open the app: it starts normally, Receive shows a QR code, scanning it transfers (before, the app did nothing without a network)
- [ ] The progress bar is empty at 0% and fills as the transfer goes (before, it looked full and blue)

## Audit round 1: transfer stability (A1, A2, A3, A4, A7)

- [ ] A1: start a send, press Back: a dialog asks whether to stop. "Keep going" continues the transfer
- [ ] A1: cancel a running send, then send again at once to the same phone: the second send finishes; no "failed" appears on it
- [ ] A1: over the QR hotspot, cancel and immediately scan and send again: the second transfer is not cut off
- [ ] A2: during a transfer, swipe the app away from the recent apps: the "transfer" notification disappears within a few seconds
- [ ] A2: finish a transfer, close the app with Back from the home screen: no Zajel notification stays
- [ ] A3: start a big send, then kill the sender's app (swipe it away). Open it again, wait about 10 seconds and send again: it is accepted, not "busy"
- [ ] A3: while phone A is sending to B, phone C sends to B: C sees "the other device is busy", in Arabic
- [ ] A4: rename a file so its name ends with a space or a dot (a file manager allows it) and send it together with other files: all arrive
- [ ] A7: open the LocalSend app on the receiver, then open Zajel: Zajel still starts, is found by the sender and receives
- [ ] Interop: send one file from the official LocalSend app to Zajel and one from Zajel to LocalSend

## Audit round 2: choosing files (C1, C2, C3, C4, C5, C6)

- [ ] C1: start a send and cancel it, or let it fail (turn the receiver's Wi-Fi off). Press Send on the home screen: the same files are still selected
- [ ] C1: on the failed screen, "Try again" sends to the same phone; "Choose another device" opens the radar; Back from the radar goes to the home screen
- [ ] C1: after a send that succeeded, the next send starts with nothing selected
- [ ] C3: tap a big video in the Videos tab: a spinner shows on its tile until it is selected. Tap it twice quickly: it is counted once
- [ ] C4/C6: pick photos, an app and a file. Each tab shows its own; the send bar counts all; "review" lists all
- [ ] C2: in the Files tab choose a file of 1 GB or more: the button says "Preparing the files…" until it appears in the list. (The wait itself is not gone: the system picker still copies the file. Photos and Videos tabs do not have it.)
- [ ] C2: choose the same file twice: it is listed once
- [ ] C5: select two photos, open the Files tab's picker, switch to another heavy app until Zajel is closed by Android, come back within ten minutes: the two photos are still selected
- [ ] C6: with nothing selected, scan a receiver's QR code, pick a file, press Send: the transfer starts at once (no radar)
- [ ] C6: after "Done", press Back: the home screen, not the launcher. "Send more", then Back: the home screen
- [ ] Hotspot with Wi-Fi off: switch Wi-Fi off, press Receive: a QR code appears (if this phone cannot do it, the "turn Wi-Fi on" message appears instead)

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
