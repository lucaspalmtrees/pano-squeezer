# CLAUDE.md – pano-squeezer

Native macOS app that losslessly "desqueezes" anamorphic DNG photos by setting the
DNG tag `DefaultScale` (0xC61E) in the raw IFD.

## Non-negotiable rules
1. **Never modify originals.** Source files are opened read-only. Tests work on copies only.
2. **Never touch image data.** The output contains every byte of the original at the same
   position. Exactly one 4-byte IFD pointer is changed; everything new is appended at the end.
   This is verified after every write (`OutputVerifier`). On failure: delete output, report.
3. **No network access, no telemetry.** Only exception: donation/GitHub links opened by the user.
4. **No runtime dependencies.** Swift + Apple frameworks only. exiftool is allowed in tests only.
5. **Never commit own photos** (`testdata/local/` is git-ignored; DNGs contain serial numbers/GPS).

## DNG logic (core)
- DNG = TIFF 6.0. `DefaultScale`: tag 0xC61E, type RATIONAL, count 2, `[horizontal, vertical]`.
  Horizontal factor f → `(f, 1)`, vertical → `(1, f)`; stored as reduced fraction (1.33 → 133/100, 1.5 → 3/2).
- Raw IFD = the IFD with `NewSubFileType` (0x00FE) == 0. May be IFD0 or a SubIFD (0x014A) — search, don't assume.
- The pointer to an IFD can live in: header (byte 4), previous IFD's next field, SubIFDs value field (count 1),
  or an element of the SubIFDs array (count > 1).
- Write (append strategy): copy original to `.<name>.partial`, append the 16-byte DefaultScale value and a copy of
  the raw IFD (entries unchanged, DefaultScale added/replaced, sorted by tag, word-aligned), redirect the one pointer,
  verify, copy dates, rename atomically. Never move existing bytes (maker notes contain absolute offsets).
- Skip with reason: DefaultScale already ≠ 1/1, no or several raw IFDs, BigTIFF / > 4 GB, damaged file,
  output already exists (never overwrite).
- Output folder: `Desqueezed 1.33x` / `Desqueezed 1.33x vertical`; subfolders mirrored; earlier output folders,
  hidden files and `._*` files are ignored when scanning.
- Lightroom Classic / Desktop / Camera Raw honour the tag; Lightroom mobile, Finder and Quick Look do not.

## Releases
- Push a `v*` tag, or start Actions → Release → Run workflow with a version (creates tag + release).
- Release notes come from the matching `CHANGELOG.md` section. Notarization is prepared but disabled (`NOTARIZE`).

## Layout
- `Sources/PanoSqueezerCore/` – pure logic, Foundation only, must build/test on Linux.
  - `TIFFStructure.swift` parser (header + IFDs only, via FileHandle/seek, bounds/cycle checks)
  - `DNGDesqueezer.swift` append-strategy writer, `OutputVerifier.swift` post-write check
  - `SqueezeFactor.swift` factor parsing (“1.33”, “1,5”, “2”) → reduced fraction
  - `Scanner.swift` / `BatchConverter.swift` folder scanning and batch processing
- `Sources/pano-squeezer-cli/` – test CLI: `pano-squeezer-cli --factor 1.33 [--vertical] [--out DIR] <files|folders…>`
- `Sources/PanoSqueezer/` – SwiftUI app, wrapped in `#if os(macOS)` with a stub `main` elsewhere.
- `scripts/` – `build-app.sh` (universal .app, ad-hoc signed), `make-icon.sh`, `integration-test.sh`.

## Commands
- `swift build` / `swift test` (works on macOS and Linux)
- `scripts/build-app.sh` → `dist/pano-squeezer.app` (macOS only)
- `scripts/integration-test.sh` → CLI + exiftool checks on real DNGs (macOS/Linux with exiftool)

## Conventions
- Keep code simple; comment where the TIFF/DNG structure is not obvious.
- Small commits with clear messages. Ask instead of guessing, especially for anything that writes files.
- UI language v1: English (German localization planned later).
- No Claude attribution lines (`Co-Authored-By`, `Claude-Session`) in commit messages.
