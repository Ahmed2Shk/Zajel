# Zajel — Design

Put the Stitch exports in this folder (PNG screenshots and/or HTML per screen). Name them by screen: `01-home.png`, `02-file-picker.png`, …

## Tokens — theme "Night and Lightning" (ليل وبرق)

| Token | Value | Use |
| --- | --- | --- |
| background-dark | #0E1116 | default (dark) background |
| surface-dark | #171B22 | cards, lists, sheets |
| background-light | #F7F8FA | light theme background |
| primary | #C6F432 | send actions, progress bars |
| secondary | #38BDF8 | receive actions |
| success | #22C55E | transfer complete |
| error | #F43F5E | failure, cancel |
| font-arabic | IBM Plex Sans Arabic | all Arabic text |
| font-latin | Inter | English text and numbers |
| radius | 20px | all components |

Dark mode is the default. Primary text on `primary` (#C6F432) must be dark (#0E1116) for contrast.

## Stitch exports (layout reference only)

`01-home.png` … `08-settings.png`, `html/` and `DESIGN.md` in this folder come from Stitch. The tokens table above is the single source of truth.

- Do not copy colors from `DESIGN.md` or `html/`. Stitch drifted: background `#111319`, secondary `#00A6E0`, error `#FFB4AB`. Use the tokens above through ThemeData.
- Take layout, spacing and hierarchy from the PNGs. Sample names, devices and numbers in them are placeholders.
- Stitch added things outside the screen list below (bottom navigation, "direct link" card, active-transfer card, history filters). Do not build them unless the spec asks.
- Home has an English "Home" title; all user-facing strings go through ARB files.
- No light-theme export exists. Build it from the `background-light` token.

## Screens

1. Home: Send and Receive buttons, QR scan icon in top bar, recent transfers
2. File picker: Photos, Videos, Apps, Files tabs, multi-select, sticky "Send (n)" bar
3. Discovery: radar around the user's avatar, devices as bubbles, "Show QR" and "Scan QR"
4. QR show: large QR + short PIN
5. QR scan: full-screen camera with scan frame
6. Transfer progress: big MB/s number, ETA, per-file list, cancel
7. Done: success, "Open files", "Send more"
8. Settings: device name, download folder, language, theme, PIN

## Stitch prompt

```text
Design a mobile app called "Zajel" (زاجل), an offline, ad-free file transfer app. Arabic-first (RTL) with English support.

Style: dark mode first, minimal and fast-feeling. Background #0E1116, surfaces #171B22, primary accent electric lime #C6F432 (send actions, progress), secondary sky blue #38BDF8 (receive actions), success #22C55E, error #F43F5E. Fonts: IBM Plex Sans Arabic + Inter. Corner radius 20px, generous spacing, subtle glow on the accent color. Include a light theme variant (#F7F8FA background).

Screens:
1. Home: two large buttons, Send (lime) and Receive (sky blue), a small QR scan icon in the top bar, recent transfers below.
2. File picker: tabs for Photos, Videos, Apps, Files, with multi-select and a sticky "Send (n)" bar.
3. Discovery: radar animation around the user's avatar, nearby devices appear as bubbles with device icons; two secondary buttons at the bottom: "Show QR" and "Scan QR".
4. QR show screen: large QR code for hotspot connection with a short PIN under it.
5. QR scan screen: full-screen camera with a rounded scan frame and a hint line.
6. Transfer progress: big speed number in MB/s, ETA, per-file progress list, cancel button.
7. Done: success state with "Open files" and "Send more".
8. Settings: device name, download folder, language, theme, security PIN.
```
