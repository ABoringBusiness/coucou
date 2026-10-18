# HeyApex Eye — branding overlay on Coucou

This fork ships Louis Raillé's [Coucou](https://github.com/Louis-CFM/coucou) as
**HeyApex Eye**. It exists as a thin overlay rather than a rewrite, because
upstream ships roughly 25 commits a day and anything broader turns every sync
into a conflict.

## Licence position

The upstream **code is MIT** — see `LICENSE`, whose copyright notice stays.
The **brand and artwork are not**: `LICENSE-ASSETS.md` reserves the names
*Coucou* and *Mochi*, the Mochi character, the app and menu bar icons, the
sounds, and the media under `docs/` and `design/`.

So replacing those is a condition of shipping, not a preference.

| asset | status |
|---|---|
| `Assets.xcassets/AppIcon.appiconset` | replaced — HeyApex icon, all 10 sizes |
| `Assets.xcassets/MenuBarIcon.imageset` | replaced — generated HeyApex template mark |
| `Resources/sounds/*.wav` (29) | replaced — synthesized placeholders, same names and format |
| **Mochi character** | **NOT replaced — see below** |
| `docs/media`, `design/` | not shipped in the app bundle; leave or strip before distribution |

### Mochi is still outstanding

Mochi is drawn in code, not stored as an asset, across 64 source files. The
licence reserves the character's "design, look, expressions and animations",
so a rename does not clear it — it needs a HeyApex companion character to take
its place. That is design work, and it is the one blocker before this can ship
publicly.

## What is branded, and how

- **Identity** — `PRODUCT_NAME` and the bundle identifiers in `project.pbxproj`.
  An `.xcconfig` overlay was considered and rejected on the evidence: upstream
  touched that file in 53 commits last month but the identity lines in only 3
  commits in 90 days, so direct edits are the lower-risk option and attaching an
  xcconfig means hand-editing pbxproj structure.
- **Display strings** — 12 SwiftUI `Text`/`Label` literals, plus English value
  overrides in `Localizable.xcstrings`. Overriding the VALUE rather than the key
  keeps upstream's string table intact and merges cleanly.
- **Attribution** — `Text("Coucou · github.com/Louis-CFM/coucou")` is left
  exactly as upstream wrote it.

## What must never be renamed

These are contracts. Renaming them trades working data for cosmetics:

- `group.fr.louisraille.Coucou` — the App Group shared with the widgets and the
  iPhone companion. Renaming orphans everything stored under it.
- `~/Library/Application Support/NotchBuddy/` and `nb.sock` — **the HeyApex
  Electron bridge hardcodes this path** (`electron/terminal/coucou-bridge.js`).
- `~/.config/*/plugins/coucou.*` — the app refuses to delete plugin files it did
  not generate, matched by name.
- `UserDefaults` keys and Swift type names.

## Staying current

```sh
git fetch upstream && git merge upstream/main
```

The overlay touches ~20 files, none of them hot, so this should stay cheap.
