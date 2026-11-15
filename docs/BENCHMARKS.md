# Zajel — Benchmarks

Phase 2 target: **20–40 MB/s** between two modern 5 GHz Android phones, 1 GB file.
Real numbers need two phones (see `docs/TESTING.md`, Phase 2). Nothing below is a phone result.

## Loopback, Dart data path (Windows desktop, one process)

Run with `ZAJEL_SLOW=1 flutter test test/core/benchmark_loopback_test.dart`.
Sender and receiver run in the **same Dart isolate**, so TLS encrypt, TLS decrypt, disk write and
hashing all share one thread. These numbers measure the cost of the Dart code, not a network.
`flutter test` also runs in JIT/debug mode, which is slower than a release build.

| Date | Path | File | MB/s | Notes |
| --- | --- | --- | --- | --- |
| 2026-10-31 | Network only, no disk (`/zajel/benchmark`) | 1 GB | 19.3 | connect 181 ms |
| 2026-10-31 | Single stream, plain LocalSend upload | 1 GB | 12.0 | baseline ("before") |
| 2026-10-31 | Chunked, 1 connection, 8 MB chunks | 1 GB | 14.4 | |
| 2026-10-31 | Chunked, 2 connections | 1 GB | 13.1 | |
| 2026-10-31 | Chunked, 3 connections | 1 GB | 12.4 | |
| 2026-10-31 | Chunked, 4 connections | 1 GB | 10.8 | |

### What this tells us

- More connections do **not** help here, and cost a little. Expected: one thread is the bottleneck, so
  extra sockets only add overhead. Parallel connections help when the limit is per-connection
  (TCP window, Wi-Fi scheduling) and the two ends run on different CPUs. That can only be measured on
  two phones.
- Network-only (19 MB/s) is the ceiling of Dart's TLS and socket handling on this machine with both
  sides on one thread. Disk write plus SHA-256 take it down to 12–14 MB/s. This is why the plan moves
  the Android data path to Kotlin (NIO, `FileChannel`, platform TLS with hardware crypto): the Dart path
  alone is unlikely to reach 20–40 MB/s.
- The 1 GB test keeps memory flat (RSS grew 10–19 MB), so streaming is correct.

## Phones (fill in during Phase 2 testing)

Read from the receivers' exported logs (time between the first and the last committed chunk), so these
are real transfers, not the speed test. Phones: one Android 12 and one Android 13 (Xiaomi builds
`SKQ1.211019.001` and `TKQ1.221114.001`).

| Date | Phones | Band | Path | File | MB/s | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-11-05 | A12 -> A13 | hotspot | QR hotspot, native data path | 494 MB video | ~28 | 518 MB in 18 s |
| 2026-11-05 | A12 -> A13 | hotspot | QR hotspot, native data path | 575 MB video | ~31 | 603 MB in 19.6 s |
| 2026-11-13 | A12 -> A13 | hotspot | QR hotspot, native data path | 1.2 GB video | ~32 | first 168 MB in 5.2 s, then cancelled |
| 2026-11-11 | A13 -> A12 | hotspot, band unknown | QR hotspot hosted by the A12 phone | 1.1 GB video | ~7 | 151 MB in 20 s, then cancelled |
| 2026-11-13 | A12 -> A13 | 5 GHz, link 585 / 195 Mbps | shared router | 1.3 GB video | 0.2-0.3 | on screen; no chunk landed in 27 s |
| 2026-11-13 | A13 -> A12 | hotspot, band unknown | QR hotspot hosted by the A12 phone | 841 MB video | ~6.3 | 882 MB in 140 s, complete |
| 2026-11-15 | A12 -> A13 | hotspot on 2462 MHz (2.4 GHz), link 96 Mbps, signal -16 dBm | QR hotspot hosted by the A13 phone | 457 MB video | ~1.3 | 68 MB in 49 s, then cancelled; the host was on a different, 192.168.0.x Wi-Fi that day |

**The hotspot's band decides the speed, and the app cannot choose it.** The same two phones, the same
host, gave ~30 MB/s on 2026-11-05 and 2026-11-13 and 1.3 MB/s on 2026-11-15. The sender's log line for
the slow run says the hotspot was on 2.4 GHz with a 96 Mbps link. On the fast days the host was connected
to a 5 GHz Wi-Fi. The likely rule (not verified by a controlled test): a LocalOnlyHotspot shares the
radio with the phone's own Wi-Fi connection, so it lands on that connection's channel; on a 2.4 GHz
Wi-Fi, or with no connection, it is a 2.4 GHz hotspot. A Wi-Fi Direct group can ask for 5 GHz
(the A13 phone created one on 5180 MHz on 2026-11-13), which is the reason to make that transport work.

The Phase 2 target (20-40 MB/s) is met on the direct link when the Android 13 phone hosts the hotspot.
With the Android 12 phone hosting it was about 7 MB/s; the likely reason is that its hotspot runs on
2.4 GHz (an app cannot choose the band of a LocalOnlyHotspot), but that was not confirmed. Over the shared router the same code gives
0.2-0.3 MB/s while the radio link itself reports hundreds of Mbps: that network limits traffic between
its clients, and no transfer code can change it. The answer is to leave the router: see "Hotspot offer"
in `docs/ZAJEL_EXTENSIONS.md`.

## Same-LAN (router) vs QR hotspot — developer report

Reported on two phones: a transfer over the shared router (radar) stayed near **2 MB/s**, while the
same transfer over the QR hotspot (direct 5 GHz link) reached **30 MB/s**. Both use the same transfer
engine, so the network route was the difference — but one code path made the router case much worse
than it had to be:

- Files between 1 MB and 8 MB went through `_uploadOne`: **one plain TCP stream**. A single stream is
  limited by its TCP window divided by the round-trip time, so a router (high RTT) was far slower than
  a direct hotspot (low RTT), where the window is never the limit.
- Done: a Zajel-to-Zajel upload splits **any file of 1 MB or more** into pieces, so every connection
  carries one (`UploadOptions.pieceSizeFor`: 3 MB goes as three 1 MB pieces, 20 MB as four 5 MB pieces,
  big files as 8 MB pieces). On an Android receiver these pieces also take the native data path instead
  of the Dart upload route, which hashes every byte. Tested on loopback; not measured on phones.
- Done: one `HttpClient` is reused for the whole batch, so the TLS connections stay open across files
  instead of a fresh handshake per file. Not measured on phones.

The same `slowLinkHint` still fires below 3 MB/s after 16 MB, telling the user to switch to QR or
Wi-Fi Direct. Measure the router path again on two phones to record the new number here.


## Not measured yet

- The Kotlin native data path has been compiled and its Dart side tested against a stand-in, but it has
  never run on a phone. Its speed is unknown until the Phase 2 test on two Android phones.
- Parallel connections may help on real Wi-Fi even though they did not help on loopback. The speed-test
  screen sends one stream, so compare `UploadOptions(parallel: 1)` and `parallel: 4` with real transfers of a
  1 GB file on two phones before choosing the default.
- Many small files as one tar request is implemented and tested on loopback, but its speed-up on real
  Wi-Fi has not been measured.
