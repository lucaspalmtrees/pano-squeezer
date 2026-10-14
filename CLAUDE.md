# CLAUDE.md – pano-squeezer

Native macOS app that losslessly "desqueezes" anamorphic DNG photos by setting the
DNG tag `DefaultScale` (0xC61E) in the raw IFD. Full specification: `SPEC.md`.

## Non-negotiable rules
1. **Never modify originals.** Source files are opened read-only. Tests work on copies only.
2. **Never touch image data.** The output contains every byte of the original at the same
   position. Exactly one 4-byte IFD pointer is changed; everything new is appended at the end.
   This is verified after every write (`OutputVerifier`). On failure: delete output, report.
3. **No network access, no telemetry.** Only exception: donation/GitHub links opened by the user.
4. **No runtime dependencies.** Swift + Apple frameworks only. exiftool is allowed in tests only.
5. **Never commit own photos** (`testdata/local/` is git-ignored; DNGs contain serial numbers/GPS).

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
- UI language v1: English.
