---
name: Kinetic Void Utility
colors:
  surface: '#111319'
  surface-dim: '#111319'
  surface-bright: '#36393f'
  surface-container-lowest: '#0b0e13'
  surface-container-low: '#191c21'
  surface-container: '#1d2025'
  surface-container-high: '#272a30'
  surface-container-highest: '#32353a'
  on-surface: '#e1e2e9'
  on-surface-variant: '#c4c9ae'
  inverse-surface: '#e1e2e9'
  inverse-on-surface: '#2e3036'
  outline: '#8e937a'
  outline-variant: '#444934'
  surface-tint: '#aad600'
  primary: '#ffffff'
  on-primary: '#283500'
  primary-container: '#c5f331'
  on-primary-container: '#556d00'
  inverse-primary: '#506600'
  secondary: '#7bd0ff'
  on-secondary: '#00354a'
  secondary-container: '#00a6e0'
  on-secondary-container: '#00374d'
  tertiary: '#ffffff'
  on-tertiary: '#003915'
  tertiary-container: '#6bff8f'
  on-tertiary-container: '#007432'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#c5f331'
  primary-fixed-dim: '#aad600'
  on-primary-fixed: '#161f00'
  on-primary-fixed-variant: '#3b4d00'
  secondary-fixed: '#c4e7ff'
  secondary-fixed-dim: '#7bd0ff'
  on-secondary-fixed: '#001e2c'
  on-secondary-fixed-variant: '#004c69'
  tertiary-fixed: '#6bff8f'
  tertiary-fixed-dim: '#4ae176'
  on-tertiary-fixed: '#002109'
  on-tertiary-fixed-variant: '#005321'
  background: '#111319'
  on-background: '#e1e2e9'
  surface-variant: '#32353a'
typography:
  display-hero:
    fontFamily: IBM Plex Sans
    fontSize: 44px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  display-hero-mobile:
    fontFamily: IBM Plex Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg:
    fontFamily: IBM Plex Sans
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  headline-md:
    fontFamily: IBM Plex Sans
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 30px
  headline-sm:
    fontFamily: IBM Plex Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 26px
  body-lg:
    fontFamily: IBM Plex Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 26px
  body-md:
    fontFamily: IBM Plex Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 22px
  body-sm:
    fontFamily: IBM Plex Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  label-numeric:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-transfer-speed:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 24px
    letterSpacing: -0.01em
  label-code:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 20px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system expresses high-velocity physical telecommunication rendered in sleek digital hardware aesthetics. Designed Arabic-first (`dir="rtl"`), it balances the technical precision of developer-grade command surfaces with the immediate, touch-first ergonomics of mobile peer-to-peer file transfer.

### Design Principles
- **Hardware-Level Utilitarianism:** Visual density and high-contrast cues prioritize rapid decision-making: discovering peers, confirming payloads, and monitoring real-time throughput.
- **Bipolar Kinetic Anchoring:** The system splits user intent into two vivid kinetic color poles: "Send" (Electric Lime) pushes outward with energetic emission, while "Receive" (Vibrant Sky) pulls inward with receptive clarity.
- **RTL-Native Fluidity:** Spatial flows, progress arcs, and radial radar telemetry originate natively from right to left, honoring Arabic typography without mirroring distortions or clumsy adaptations.
- **Atmospheric Dark Void:** Default dark mode evokes deep local networking voids with crisp surface delineation, preventing OLED battery drain during massive transfers while supporting an equally crisp light-mode counterpart for direct sun visibility.

## Colors

The palette uses a deliberate dual-accent engine on top of a low-noise charcoal infrastructure.

### Functional Roles
- **Primary Send Accent (`#C6F432` - Electric Lime):** Outgoing operations, transmission CTA triggers, outgoing radar beacons, and positive action nodes. In dark mode, pair with `#0E1116` foreground glyphs for maximum contrast.
- **Secondary Receive Accent (`#38BDF8` - Sky Blue):** Incoming requests, peer discovery listening mode, inbound packet indicators, and receptive statuses.
- **Success (`#22C55E`):** Transfer completed, checksum verified, connection established.
- **Error & Danger (`#F43F5E`):** Interrupted socket, Wi-Fi Direct failure, storage limit exceeded, cancel transmission.
- **Surfaces & Layers (Dark Mode):**
  - Canvas Base: `#0E1116`
  - Layer 1 (Cards, Sheets): `#171B22`
  - Layer 2 (Raised chips, input wells): `#1E242E`
  - Structural Borders: `#262C36`
  - Text Primary: `#FFFFFF`
  - Text Muted: `#94A3B8`
- **Light Mode Adaptation:**
  - Canvas Base: `#F7F8FA`
  - Surface: `#FFFFFF`
  - Border & Dividers: `#E2E8F0`
  - Text Primary: `#0F172A`
  - Text Muted: `#64748B`
  - Electric Lime shifts to `#84B800` or retains `#C6F432` against dark interactive badges for visual retention.

## Typography

The typographic hierarchy implements an asymmetric dual-script strategy:

- **Arabic Structural Layer (`IBM Plex Sans Arabic`):** Handles all headlines, body copy, and primary action statements. IBM Plex Sans Arabic offers mechanical geometry and engineered proportions that harmonize with high-tech utilities, eliminating the traditional ornamental sprawl in favor of compact vertical rhythm.
- **Latin & Telemetry Layer (`Inter`):** Assigned to numeric transfers, byte scales (e.g., `84.2 MB/s`, `4.1 GB`), device hardware IDs, IP/port pairings, and session PINs. 
- **Bilingual Stacking:** When file names combine Arabic and Latin characters, line boxes reserve consistent 1.5x leading to avoid glyph collision between diacritics and ascenders.
- **Numerals:** Standardize on Western Arabic figures (`0-9`) for throughput, transfer progress, and technical metadata to ensure instantaneous recognition under field conditions.

## Layout & Spacing

The layout is built for rapid one-handed mobile interaction within an offline field utility environment.

### Grid & Ergonomic Philosophy
- **RTL Fluid Columns:** Uses a 4-column layout on mobile devices (`<640px`) expanding to 8 columns on foldables and tablets. Layout elements align to the right margin first, driving thumb interactions toward bottom-right anchor spots.
- **Thumb-Zone Prioritization:** Primary send/receive switches, drawer dismissals, and radar triggers are pinned within the bottom 40% of the mobile viewport.
- **Spacing Rhythm:** Standard 4px base increments. Gutters stay compact (`16px`) to maximize horizontal screen real estate for deep file names and directory trees. Margins maintain a tactile `20px` border to keep touch targets safe from device edge gestures.
- **Adapting to Foldables & Tablets:** At `>=768px`, radar discovery shifts to a persistent right pane while directory browsing, queue selection, and history populate the left 60% of the canvas.

## Elevation & Depth

Visual hierarchy rejects fuzzy, spread-out drop shadows in favor of crisp darkroom layering, low-contrast structural borders, and electric luminescent halos.

### Elevation Levels
- **Ground (`#0E1116`):** The default unlit canvas.
- **Level 1 (`#171B22` with border `1px solid #262C36`):** Standard container tier for peer discovery cards, file list items, and summary widgets.
- **Level 2 (`#1E242E` with border `1px solid #333B48`):** Raised interactive elements, active popovers, bottom action trays, and drawer surfaces.
- **Level 3 (Modal Confirmation):** High-level overlay backed by `rgba(14, 17, 22, 0.85)` with a backdrop blur of `24px`.

### Luminescent Glow Tokens
- **Send Pulse:** `0 0 24px -4px rgba(198, 244, 50, 0.35)` applied to the active broadcast orb and confirmation trigger.
- **Receive Aura:** `0 0 24px -4px rgba(56, 189, 248, 0.35)` applied to listener radar rings and pairing prompts.
- **Flat Inset Border:** All cards utilize an inner or structural border (`#262C36`) to cleanly separate elements without requiring drop shadows that bleed into OLED blacks.

## Shapes

The design system enforces a distinctive `20px` curvature footprint across primary containers, balancing technical rigidity with friendly tactile softness.

### Shape Tokens
- **Container Curvature (`20px`):** Cards, bottom sheets, peer status panels, and main module enclosures use `border-radius: 20px`.
- **Action Triggers & Pills (`9999px`):** CTAs, status tags, mode toggle selectors, and connection pills use complete circular rounding for clear tactile affordance.
- **Nested Inner Surfaces (`12px`):** File format badges, thumbnail wrappers, and secondary buttons nested inside a `20px` parent container drop to `12px` radius to maintain optical concentricity.
- **Radar Nodes (`Circle`):** Peer avatars, telemetry wave pulses, and signal indicators maintain strict 1:1 circular symmetry.

## Components

### Buttons
- **Send Action Button (Primary):** Filled with `#C6F432`, foreground `#0E1116`, weight 700. Features an ambient lime edge glow. Minimum height `56px`, corner radius `9999px`. Dynamic press scales down to `0.97` for instantaneous tactile feedback.
- **Receive Action Button (Secondary):** Filled with `#38BDF8`, foreground `#0E1116`, weight 700. Ambient cyan glow. Same structural sizing.
- **Ghost Utility Button:** Background `#171B22`, border `1px solid #262C36`, foreground `#FFFFFF`. Hover/active shifts background to `#1E242E`.

### Cards & Peer Nodes
- **Peer Discovery Card:** Encased in `#171B22` with a `20px` radius. Shows an avatar orb on the right (RTL), followed by device name in `IBM Plex Sans` and connection protocol (Wi-Fi Direct / Hotspot) in `Inter`. Active state features a 1.5px `#C6F432` or `#38BDF8` outline.
- **Transfer Progress Card:** Houses a continuous linear progress bar with dual-color kinetic flow: background `#262C36`, fill gradient from `#C6F432` to `#38BDF8`. Displays time-remaining metrics in `Inter` alongside an Arabic file type label.

### Chips & Badges
- **Status Chips:** Height `28px`, radius `9999px`, padding `0 12px`.
  - Transmitting: Background `rgba(198, 244, 50, 0.12)`, text `#C6F432`.
  - Listening: Background `rgba(56, 189, 248, 0.12)`, text `#38BDF8`.
  - Offline: Background `rgba(148, 163, 184, 0.1)`, text `#94A3B8`.

### Lists & File Rows
- **Payload Queue Row:** Height `64px`. Displays an icon badge on the right, title truncated with middle ellipsis for long file extensions, file size (`Inter`) anchored on the left, and a contextual quick-action button on the far left edge. Separators use `1px solid #262C36` with right indent aligning to text start.

### Radar & P2P Discovery Surface
- **Telemetry Canvas:** Concentric circular rings expanding from the device center with `1px solid #262C36`.
- **Ping Wave:** Animated SVG pulse scaling outward with variable opacity from `0.6` down to `0.0`.
- **Peer Pin:** Pulsing circle holding a device silhouette or avatar with dynamic distance ping badges floating directly beneath.

### Inputs & PIN Keys
- **One-Time Pairing Code:** Set of 4 to 6 separate input blocks. Background `#171B22`, border `2px solid #262C36`, text centered in `Inter` at `24px` bold. Focus shifts border to `#C6F432` with a subtle glow.