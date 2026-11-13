# Zajel protocol extensions

Zajel speaks LocalSend v2 unchanged. Between two Zajel apps it adds optional speed features.
They are negotiated with HTTP headers, which the official LocalSend apps ignore, so interop is never affected.

## Negotiation

1. The sender adds `x-zajel-extension: 1` to `POST /prepare-upload`.
2. A Zajel receiver answers with the same header. Only then does the sender use the extensions.
3. A receiver with a native data server also answers `x-zajel-data-port: <port>`.

A stock receiver sends neither header, so the sender uses the plain LocalSend upload.

## Chunked, parallel upload

`POST /api/localsend/v2/upload?sessionId=&fileId=&token=&offset=<n>` with `Content-Length` = chunk length.

- Chunks are at most 8 MB and go over up to 4 connections, in any order. A file between 1 MB and 32 MB is
  cut into equal pieces (at least 1 MB each) so that every connection carries one.
- The receiver writes each chunk at its offset, tracks the byte ranges received, and finishes the file when
  the ranges cover it. A retried chunk is harmless. If the file has a `sha256`, it is checked at the end
  (`422` on mismatch).
- Files smaller than 1 MB use the plain whole-file upload.

## Resume

`GET /api/localsend/v2/zajel/progress?sessionId=&fileId=&token=` returns `{"size", "done", "ranges": [[start, end], ...]}`.
A sender that lost its connection calls `upload` again on the same session; chunked files skip what the
receiver already holds. Dropped connections are retried automatically (5 times, 2 s apart).
Resume works within a session. If the app restarts, the session is gone and the transfer starts over.

A request whose answer was lost is safe to repeat. Uploading a file that is already complete is answered
`200` and its body is dropped (never a second copy). For 60 seconds after the last file of a session, the
receiver still answers `progress`, `tar-status` and repeated uploads for that session, so a sender that
missed the final answer learns the transfer is done. When a chunk is refused, the sender asks `progress`
before failing: a chunk the receiver holds counts as sent.

A file that was still arriving when the receiver cancelled the session is not saved.

A session with no traffic for 2 minutes is dropped on the receiver, which removes the partial file and
releases the foreground service.

## Native data port (Android receivers)

The receiver starts a Kotlin TLS server (`NativeDataServer`) on a free port and advertises it in
`x-zajel-data-port`. It accepts only `POST /api/localsend/v2/upload` chunk requests, writes the body to the
reserved `.zajel-part` file with `FileChannel`, then asks Dart to confirm the chunk and answers with Dart's
status. File bytes never enter Dart on this path.

Dart stays in charge of authorization: it registers each accepted file (session, file, token, path, size,
sender address) and unregisters the session when it ends.

If the sender cannot reach the data port before any chunk got through, it falls back to the main port. The
main port refuses a Dart-route chunk (`409`) once the native server has written to that file, because
opening the file for Dart would truncate it.

Plain (non-chunked) uploads, which is everything a stock LocalSend sender does, still go through Dart.
So interop with the official apps does not get the native speed-up.

## Hotspot offer (automatic direct link)

`GET /api/localsend/v2/zajel/direct` returns `{"code": "zajel://pair?d=..."}`: the pairing code of the
hotspot the receiver is hosting, the same one its QR screen shows. `404` when it hosts none, and always
`404` when a permanent PIN is set (that PIN has to be typed, never bypassed).

A sender that taps a device found on the shared Wi-Fi asks this first. With a code, it joins the hotspot
and sends over it, keeping the Wi-Fi as the fallback (and presenting the pairing token there too). So when
the receiver is on its "Receive" screen, one tap on the sender moves the transfer off a slow router, with
no scanning. The code is validated like a scanned one (private IPv4 only) and must carry the fingerprint
of the device that was tapped.

What this gives away: the hotspot password and the one-time pairing token, to any device on the same
network that asks while the QR screen is open. That is what the open QR screen itself shows. It does not
skip the owner's Accept dialog.

## Speed test

`POST /api/localsend/v2/zajel/benchmark` reads and discards the body and answers `{"bytes", "ms"}`.
No file is written. Zajel receivers only.

## Many small files as one archive

When at least 4 files smaller than 256 KB are accepted, a Zajel sender sends them as one tar archive instead
of one request each. The receiver offers it with `x-zajel-tar-token` in the `prepare-upload` response.

- `POST /api/localsend/v2/zajel/tar?sessionId=&token=<tarToken>`, body is a ustar archive.
- **Entry names are file ids, never paths.** The receiver maps each id to the destination it already chose
  for that file (sanitized as always), so an archive cannot write anywhere else. Unknown ids, a size that
  differs from `prepare-upload`, non-regular entries (directories, symlinks), a bad header checksum, a
  truncated archive or a missing end marker are all refused with `400`. A `sha256` mismatch is `422`.
- Files finish one by one, so an interrupted archive keeps everything that completed.
- `GET /api/localsend/v2/zajel/tar-status?sessionId=&token=` lists the ids already received, so a resumed
  upload sends only the rest.
