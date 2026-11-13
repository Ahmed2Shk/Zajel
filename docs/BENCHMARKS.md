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

| Date | Phones | Band | Path | File | MB/s | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

## Same-LAN (router) vs QR hotspot — developer report

Reported on two phones: a transfer over the shared router (radar) stayed near **2 MB/s**, while the
same transfer over the QR hotspot (direct 5 GHz link) reached **30 MB/s**. Both use the same transfer
engine, so the network route was the difference — but one code path made the router case much worse
than it had to be:

- Files between 1 MB and 8 MB went through `_uploadOne`: **one plain TCP stream**. A single stream is
  limited by its TCP window divided by the round-trip time, so a router (high RTT) was far slower than
  a direct hotspot (low RTT), where the window is never the limit.
- **Not done yet:** splitting files of 1 MB or more into parallel pieces. Files under 8 MB still go
  through `_uploadOne` (the threshold is `UploadOptions.chunkSize`).
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
