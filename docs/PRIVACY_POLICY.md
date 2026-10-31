# Zajel Privacy Policy

Effective: 31 October 2026

Zajel (زاجل) moves files between nearby devices. It works without the internet, has no accounts and shows no ads.

## What Zajel collects

Nothing. Zajel has no servers, no accounts, no analytics, no advertising and no crash-reporting service. The app
makes no network requests to any server on the internet.

## What stays on your device

- **Your settings:** language, theme, device name, download folder and the PIN you choose for receiving.
- **Files you receive:** on Android 10 and later they are saved in the public folders of your phone (photos and
  videos in Pictures/Movies, music in Music, everything else in Downloads, each inside a "Zajel" folder), so the
  Gallery and the file manager can show them. Other apps that you allow to read those folders can see them, like any
  other file in them. You can delete them from there at any time.
- **A list of recent transfers** (file name, size, the other device's name, time), so the home screen can show it.
  You can clear it from the home screen.
- **A local log** of app events and errors that helps with problems. It never contains file names, file contents,
  PINs or the secret codes used during a transfer. It is kept on the device and is exported only when you choose
  "Export log" and pick where to save it.
- **A device identity** (a private key and certificate) created on first run, used to encrypt transfers and to
  recognise your device. It never leaves the device.

## How files move

Files go directly from one device to another over your local network, a hotspot or Wi-Fi Direct. Transfers are
encrypted with TLS, and the receiving person must accept them. They never pass through a server.

The optional browser page is the one exception: it uses plain HTTP, because browsers do not accept the certificates
Zajel uses. It runs only while you switch it on, shows a warning, and needs a secret link or QR code. Use it on a
network you trust.

## Permissions and why

| Permission | Why |
| --- | --- |
| Network, Wi-Fi state, multicast | Find nearby devices and transfer files. |
| Nearby devices (Android 13+) / Location (Android 12 and earlier) | Required by Android to create or join a hotspot and to use Wi-Fi Direct. Zajel does not read your location. |
| Photos and videos (Android 13+: read images, read videos; Android 12 and earlier: read storage) | Show your photos and videos as pictures in the file picker so you can choose what to send. Nothing is uploaded or stored; files leave the device only when you send them to another device. Android 14 lets you share only some photos with the app. |
| Camera | Scan a QR code from another device. Images are not stored or sent. |
| Foreground service, wake lock, notifications | Keep a transfer running with the screen off and show that one is in progress. |
| Change Wi-Fi / network state | Join the other device's hotspot or Wi-Fi Direct group. |

Zajel can list the apps on your device (the ones with a launcher icon) only so you can choose an app to send as an
APK file. This list is not stored or sent anywhere.

## Children

Zajel does not collect data, so it collects no data from children.

## Changes

If this policy changes, the new version will be published with the app and the date above updated.

## Contact

Add a contact address before publishing: ______________________
