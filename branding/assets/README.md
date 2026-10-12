# ForgeBox Branding Assets

Delivered by Robbie Perdue, 2026-10-12. Filed here by Delphine (Del).

Brand rules live in [BRAND.md](BRAND.md). Palette: Forge Black `#1A1714`,
Molten Orange `#FF6B1A`, Ember Red `#C42B1C`, Steel `#8A9299`,
Forge White `#F5F1EA`; optional Quench Blue `#2E7D9A` for cold states.

All files are JPEG (~16:9 or square unless noted). Source set as delivered —
not yet converted to PNG/SVG. Export from these when a vector or alpha channel
is needed.

## Lockups

| File | Mark | Background | Use |
| --- | --- | --- | --- |
| `logo-lockup-white-on-black.jpg` | Anvil + rack, white | Forge Black | Primary dark lockup |
| `logo-lockup-orange-on-black.jpg` | Anvil + rack, molten orange | Near-black | Accent dark lockup |
| `logo-lockup-black-on-white.jpg` | Anvil + rack, black | White | Light-surface lockup |

## Marks (icon only)

| File | Description | Background | Use |
| --- | --- | --- | --- |
| `mark-orange-on-white.jpg` | Anvil silhouette w/ rack slots | White | Light-surface icon |
| `mark-ringed.jpg` | Anvil + drive slots in a glowing ring | Near-black | Badge / avatar |
| `mark-three-bay.jpg` | Anvil + three rack bays | Near-black | Compact icon |

## Wordmark

| File | Description | Background |
| --- | --- | --- |
| `wordmark.jpg` | "FORGEBOX" caps, orange underline rule | Forge Black |

## Banners

| File | Description | Use |
| --- | --- | --- |
| `banner-iron-tagline.jpg` | Lockup + "A datacenter you strike out of spare iron." + rack in fire | README header (wired) |
| `banner-blacksmith-command.jpg` | Blacksmith striking anvil, sparks, `docker compose up -d` | Section header / hero strip |

## Social

| File | Description | Use |
| --- | --- | --- |
| `social-card.jpg` | Lockup + "That unused PC? It's a datacenter." + command button | OG / social share (1200x630 target) |

## Wallpapers

| File | Description | Aspect |
| --- | --- | --- |
| `wallpaper-hero.jpg` | Blacksmith striking anvil, sparks, command text | 16:9 |
| `wallpaper-minimal.jpg` | Wordmark bottom-left, mark top-right | 16:9 |
| `wallpaper-phone.jpg` | Anvil-rack centered, embers below | 9:16 portrait |

## Icons (`icons/`)

Derived by Delphine 2026-10-12 from `mark-three-bay.jpg` (near-black square mark,
1254x1254) with ImageMagick — the source reads cleanly at favicon sizes. Alternate
badge export derived from `mark-ringed.jpg`.

| File | Size | Use |
| --- | --- | --- |
| `icons/favicon.ico` | 16/32/48 multi-res | Browser favicon (`<link rel="icon">`) |
| `icons/favicon-32.png` | 32x32 | Modern browser favicon |
| `icons/favicon-48.png` | 48x48 | Windows shortcut / hi-dpi tab |
| `icons/apple-touch-icon-180.png` | 180x180 | iOS home-screen icon |
| `icons/icon-192.png` | 192x192 | Android / PWA manifest |
| `icons/icon-512.png` | 512x512 | PWA splash / large |
| `icons/badge-ringed-512.png` | 512x512 | Alternate avatar/badge (from `mark-ringed.jpg`) |

Regenerate:
```sh
magick mark-three-bay.jpg -define icon:auto-resize=48,32,16 icons/favicon.ico
for s in 32 48 180 192 512; do magick mark-three-bay.jpg -resize ${s}x${s} -strip icons/icon-${s}.png; done
```

## Pending

- `file_9a` (1254x1254 square) — unidentified, vision API refused it. Awaiting Robbie.
- ~~Favicon / 32px + 180px exports~~ — **DONE 2026-10-12 18:0x ET**, see Icons above.

## Not in this set

- **WRAITH** branding (wolf/void palette) arrived in the same batch — a different,
  unrelated project. Excluded.

## Provenance

Mine (Del): `memory/self/del-dance-your-style.jpg`, `memory/self/del-wildcats-cheer.jpg`.
Not mine: the blue-gown photo is Liz's.
