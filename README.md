# pano-squeezer

**Lossless desqueeze for anamorphic DNG photos on macOS:** drop a folder of DNGs, pick the squeeze factor, click *Convert* – and Lightroom shows your photos in the correct aspect ratio.

<!-- Screenshot: docs/screenshot.png (to be added) -->

## Why lossless?

pano-squeezer does **not** resample any pixels. It only adds the DNG tag `DefaultScale` to the raw image. Lightroom and Camera Raw apply this tag when rendering, so the photo appears stretched to the right aspect ratio, while the raw data stays bit-for-bit identical.

Technically, the original file is copied, a new copy of the raw image directory (IFD) with the `DefaultScale` tag is appended at the end of the file, and exactly one 4-byte pointer is redirected to it. No existing byte is moved, so maker notes and other manufacturer data remain intact. After every write, the app re-reads the result and checks byte by byte that nothing else changed; if the check fails, the output is deleted.

- Your originals are never modified (opened read-only).
- No network access, no telemetry.

## Download and first launch

1. Download the latest `pano-squeezer-x.y.z.dmg` (or `.zip`) from [Releases](https://github.com/lucaspalmtrees/pano-squeezer/releases).
2. Drag **pano-squeezer** into *Applications*.
3. The app is not signed with an Apple Developer ID, so macOS blocks the first launch:
   - Open the app once (it will be blocked), then go to **System Settings → Privacy & Security**.
   - Scroll down and click **Open Anyway** next to the message about pano-squeezer, then confirm.
   - From then on it opens normally.

Requires macOS 14 (Sonoma) or later, Apple Silicon or Intel.

## Usage

1. **Drop** a folder or DNG files onto the window (or click the drop zone to choose them).
2. **Choose** the squeeze factor of your anamorphic lens and the direction.
3. Click **Convert**. The desqueezed copies are written to a subfolder such as `Desqueezed 1.33x` (or a folder of your choice). Original file names and dates are kept; existing files are never overwritten.

### Factors and direction

- Presets: 1.25×, 1.33×, 1.5×, 1.6×, 1.8×, 2.0×, or *Custom* (1.01–4.00, two decimals).
- **Horizontal** (default): the normal case – also for portrait photos, because the lens turns with the camera.
- **Vertical**: only if the anamorphic lens itself is mounted rotated by 90°.

## Lightroom tips

- When importing, set **Build Previews** to **Standard** (not *Embedded & Sidecar*): the previews embedded in the DNG are still squeezed.
- Lightroom Classic, Lightroom (desktop/web) and Adobe Camera Raw respect `DefaultScale`; exports have the correct aspect ratio.

## Limitations

- DNG only (e.g. Leica M10 and Q2 save DNG directly). Other raw formats would need converting to DNG first.
- **Lightroom on iPhone/iPad ignores `DefaultScale`** (known issue) – photos appear squeezed there.
- Finder and Quick Look show the embedded preview, which is still squeezed.
- Other apps may or may not support `DefaultScale`.
- BigTIFF and files larger than 4 GB are not supported; files that already have a `DefaultScale` are skipped.

## Command line tool (for testing)

```sh
swift build
.build/debug/pano-squeezer-cli --factor 1.33 [--vertical] [--recursive] [--out DIR] <files|folders…>
.build/debug/pano-squeezer-cli --info photo.DNG     # show the IFD structure
```

## Building from source

```sh
swift test                 # unit tests (macOS or Linux)
scripts/integration-test.sh  # needs exiftool (brew install exiftool)
scripts/build-app.sh       # → dist/pano-squeezer.app (universal, ad-hoc signed)
```

## Support

pano-squeezer is free and open source. If it saves you time, you can support it via the *Sponsor* button on GitHub.

## License

MIT – see [LICENSE](LICENSE).

*Not affiliated with Adobe or Leica.*
