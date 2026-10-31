# Zajel — Router-free transports (Phase 3)

Status: **written and compiled, never run on a phone.** The Dart logic (QR format, pairing, route order and
fallback, error mapping, screens) is covered by automated tests with a stand-in for the phone. The Kotlin that
talks to Android (`WifiTransport.kt`) is only compiled. Test it with `docs/TESTING.md`, Phase 3.

## Order

`TransportManager` tries routes to the same device fastest first: **Wi-Fi Direct**, then a **hotspot joined by
QR**, then the **shared Wi-Fi**. A failure falls back to the next one. If none works, the failure of each is kept
so the screen can say what to fix.

## QR pairing

The receiver ("Show QR") starts a LocalOnlyHotspot, arms a one-time pairing and shows a QR code plus a 4-digit
PIN. The sender ("Scan QR") joins the hotspot, checks the certificate fingerprint from the code, and sends with
the token or PIN.

The code is `zajel://pair?d=<base64url JSON>` with: `v` (1), `ssid`, `pass`, `ip`, `port`, `fp` (certificate
SHA-256, lowercase hex), `tok` (one-time token), `pin`, `name`. A scanned code is untrusted: wrong scheme, bad
field, a non-private or non-IPv4 address, or an oversized payload is rejected. The same format is used by iOS later.

- The first accepted transfer uses the pairing up. Wrong guesses lock the sender out after 5 attempts for 60 s.
- While armed, the pairing replaces the permanent PIN (showing the code is the owner's invitation).
- The pairing and the hotspot are removed when the screen closes.

## What Android allows

- **LocalOnlyHotspot band:** the system chooses it. An app cannot ask for 5 GHz on this kind of hotspot, so
  "prefer 5 GHz" is not possible here. Wi-Fi Direct groups do request 5 GHz where the radio supports it (Android 10+).
- **Joining a hotspot:** Android 10+ shows its own approval dialog on the joining phone. Android 8 and 9 add the
  network by hand and may need the user to confirm.
- **If the phone's own hotspot is on**, starting a LocalOnlyHotspot fails (`busy`). The message says to turn it off.
- **Permissions:** Android 13+ uses `NEARBY_WIFI_DEVICES` (declared `neverForLocation`). Android 12 and earlier need
  `ACCESS_FINE_LOCATION` and Location turned on, even though no location is read.
- **Camera:** asked by the scanner. If denied, the screen says so and "Try again" restarts the camera.

## Wi-Fi Direct

Nothing starts by itself. On the discovery screen, "Wi-Fi Direct" opens a sheet to search for receivers or to make
this device visible.

- The receiver becomes group owner (5 GHz where supported) and advertises `_zajel._tcp` over Wi-Fi Direct service
  discovery with its name, fingerprint and port.
- **Android 10+:** the receiver creates the group with its own random name and password and puts them in the
  advertisement, so a sender joins without an invitation prompt. The consequence: any device nearby that reads the
  advertisement can join the group while it is up. It can only reach the transfer port, which needs TLS, a
  fingerprint match and the receiver's accept dialog. The group exists only while "visible" is on.
- **Android 8 and 9:** a normal invitation. The receiver's phone shows the system's accept dialog, so it is not
  fully automatic there.

## Not done

- No automatic Wi-Fi Direct on screen open: it needs permissions and the radio, so it is a choice.
- Wi-Fi Aware (Phase 6, iOS 26) and Bluetooth/BLE discovery are not implemented.
- Nothing here has been measured for speed.
