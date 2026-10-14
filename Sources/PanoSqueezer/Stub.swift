// The app is macOS only. On other platforms (e.g. Linux CI) this stub keeps `swift build` working.
#if !os(macOS)
@main enum Stub {
    static func main() { print("pano-squeezer app is macOS only. Use pano-squeezer-cli instead.") }
}
#endif
