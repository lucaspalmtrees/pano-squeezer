import Foundation

/// One DNG found while scanning.
public struct ScanItem: Equatable, Sendable {
    /// The DNG file.
    public var source: URL
    /// The dropped folder (or, for a dropped file, its parent folder). Output for "Same folder" goes in here.
    public var root: URL
    /// Subfolder path of `source` relative to `root` ("" if directly inside), mirrored in the output.
    public var relativeDirectory: String
}

public struct ScanResult: Equatable, Sendable {
    public var items: [ScanItem] = []
    /// Visible files that are not DNGs (hidden files and macOS "._" files are ignored silently).
    public var ignoredCount = 0
    /// Name to display: the folder name, a single file name, or "n items".
    public var displayName = ""
}

public enum DNGScanner {

    /// `.dng` extension (any case) and a TIFF header ("II*\0" / "MM\0*", or BigTIFF, which is rejected later with a reason).
    public static func isDNG(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "dng", !url.lastPathComponent.hasPrefix(".") else { return false }
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        let b = [UInt8](d)
        return (b[0] == 0x49 && b[1] == 0x49 && b[3] == 0 && (b[2] == 42 || b[2] == 43))
            || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0 && (b[3] == 42 || b[3] == 43))
    }

    public static func scan(_ inputs: [URL], includeSubfolders: Bool) -> ScanResult {
        var result = ScanResult()
        var seen = Set<String>()
        let fm = FileManager.default

        func add(_ file: URL, root: URL, relative: String) {
            let key = file.standardizedFileURL.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            if file.lastPathComponent.hasPrefix(".") { return }  // hidden, incl. "._L1000123.DNG"
            if isDNG(file) {
                result.items.append(ScanItem(source: file, root: root, relativeDirectory: relative))
            } else {
                result.ignoredCount += 1
            }
        }

        for input in inputs {
            let url = input.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                add(url, root: url.deletingLastPathComponent(), relative: "")
                continue
            }
            scanFolder(url, root: url, relative: "", recursive: includeSubfolders, add: add)
        }
        result.items.sort { $0.source.path.localizedStandardCompare($1.source.path) == .orderedAscending }

        if inputs.count == 1 {
            result.displayName = inputs[0].lastPathComponent
        } else {
            result.displayName = "\(inputs.count) items"
        }
        return result
    }

    private static func scanFolder(_ folder: URL, root: URL, relative: String, recursive: Bool,
                                   add: (URL, URL, String) -> Void) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { return }
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                // Never re-process our own output folders; skip app bundles etc.
                // Depth limit guards against symlink loops.
                if !recursive || name.hasPrefix(DesqueezeSettings.outputFolderPrefix) || url.pathExtension == "app"
                    || relative.split(separator: "/").count >= 32 {
                    continue
                }
                scanFolder(url, root: root, relative: relative.isEmpty ? name : relative + "/" + name,
                           recursive: true, add: add)
            } else {
                add(url, root, relative)
            }
        }
    }
}
