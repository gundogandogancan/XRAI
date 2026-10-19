# XRAI brand assets

| file | sha256 | note |
|---|---|---|
| `xrai_logo_source_1254.jpeg` | `2b636a50ae1ef84ed86ef8c999ce03eb91f37bd48eef9e6bce072bc721e3bc35` | Source logo supplied by the founder on 2026-10-19 (1254×1254). |
| `xrai_logo_1024.png` | `e189459a7c3185b3cdd176aa5bad5c42da8d97e4de63862302644133e482070c` | Lossless 1024×1024 PNG derived with `sips` for the future App Store icon pipeline. |

**Mark:** four curved blades meeting a central lens with a bright core; a vertical and a horizontal axis of dots; a rounded-square frame with a spectral gradient border (red → yellow → green → cyan → blue → violet) on near-black.

**Use rules (constitution §88, ADR-014):** original design system, no competitor assets. Semantic colour tokens are to be derived from this mark in P03 (`XRAIDesignSystem`): violet/lavender accent, deep near-black surface, restrained spectral accents only where meaningful, calm neutrals for reading surfaces, AA+ contrast, dark and light modes. No emoji, no fear or "scanner" imagery; "quiet discovery" tone.

**App icon:** iOS icons must be opaque squares without alpha; the gradient border and glow must be re-rendered at 1024×1024 for the asset catalog (the Home Screen applies its own mask). The PNG here is a working source, not the final icon. Icon generation is a P03 task; no network icon tools were installed (see `docs/tools/`).
