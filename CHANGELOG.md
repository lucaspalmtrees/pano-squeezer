# Changelog

All notable changes to this project are documented here.

## [0.1.1] – unreleased

### Fixed
- "Save to → Choose…" did not open the folder picker; the selection jumped back to "Same folder".

## [0.1.0] – 2026-10-14

### Added
- Lossless desqueeze of anamorphic DNGs by setting the `DefaultScale` tag in the raw IFD (append strategy, only one 4-byte pointer changed).
- Mandatory verification after each write (structure and byte-by-byte comparison).
- macOS app: drag & drop of folders and files, factor presets and custom factor, horizontal/vertical, output to subfolder or custom folder, progress with cancel, result summary with details and “Show in Finder”.
- Command line tool `pano-squeezer-cli` for testing.
- Optional donation link (Ko-fi) in the About window and after a successful conversion.
- Unit tests with synthetic DNGs, integration test with exiftool.
