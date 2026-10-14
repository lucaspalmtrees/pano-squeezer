import Foundation

public enum OutputDestination: Equatable, Sendable {
    /// Output folder inside the source folder.
    case sameFolder
    /// Output folder inside a folder chosen by the user (e.g. when the source is an SD card).
    case custom(URL)
}

public struct FileResult: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable { case converted, skipped, failed }
    public var id: String { source.path }
    public var source: URL
    public var output: URL
    public var status: Status
    public var reason: String?
}

public struct BatchSummary: Equatable, Sendable {
    public var results: [FileResult] = []
    /// Output folders that were used (for "Show in Finder").
    public var outputFolders: [URL] = []
    public var wasCancelled = false

    public var converted: Int { results.filter { $0.status == .converted }.count }
    public var skipped: Int { results.filter { $0.status == .skipped }.count }
    public var failed: Int { results.filter { $0.status == .failed }.count }

    /// "45 converted · 2 skipped · 1 failed"
    public var text: String { "\(converted) converted · \(skipped) skipped · \(failed) failed" }
}

public enum BatchConverter {

    /// The folder that receives the converted copies for an item (structure mirrored for subfolders).
    public static func outputFolder(for item: ScanItem, settings: DesqueezeSettings,
                                    destination: OutputDestination) -> URL {
        let base: URL
        switch destination {
        case .sameFolder: base = item.root
        case .custom(let url): base = url
        }
        var folder = base.appendingPathComponent(settings.outputFolderName, isDirectory: true)
        if !item.relativeDirectory.isEmpty {
            folder = folder.appendingPathComponent(item.relativeDirectory, isDirectory: true)
        }
        return folder
    }

    public static func outputURL(for item: ScanItem, settings: DesqueezeSettings,
                                 destination: OutputDestination) -> URL {
        outputFolder(for: item, settings: settings, destination: destination)
            .appendingPathComponent(item.source.lastPathComponent)
    }

    /// Converts all items sequentially. `progress(done, total, currentFileName)` is called before each file
    /// and once at the end. Never throws: every file gets a result with a reason.
    public static func run(items: [ScanItem], settings: DesqueezeSettings, destination: OutputDestination,
                           progress: (Int, Int, String) -> Void = { _, _, _ in },
                           isCancelled: () -> Bool = { false }) -> BatchSummary {
        var summary = BatchSummary()
        var folders: [URL] = []
        for (index, item) in items.enumerated() {
            if isCancelled() { summary.wasCancelled = true; break }
            progress(index, items.count, item.source.lastPathComponent)

            let out = outputURL(for: item, settings: settings, destination: destination)
            let topFolder: URL = {
                switch destination {
                case .sameFolder: return item.root.appendingPathComponent(settings.outputFolderName, isDirectory: true)
                case .custom(let url): return url.appendingPathComponent(settings.outputFolderName, isDirectory: true)
                }
            }()
            var result = FileResult(source: item.source, output: out, status: .converted, reason: nil)
            do {
                if FileManager.default.fileExists(atPath: out.path) { throw DNGError.destinationExists }
                if !folders.contains(topFolder) { folders.append(topFolder) }
                _ = try DNGDesqueezer.desqueeze(source: item.source, destination: out, settings: settings,
                                                isCancelled: isCancelled)
            } catch DNGError.cancelled {
                summary.wasCancelled = true
                break
            } catch let e as DNGError {
                result.status = e.isSkip ? .skipped : .failed
                result.reason = e.description
            } catch {
                result.status = .failed
                result.reason = error.localizedDescription
            }
            summary.results.append(result)
        }
        // Only report folders that actually exist (e.g. not if every file was skipped before writing).
        summary.outputFolders = folders.filter { FileManager.default.fileExists(atPath: $0.path) }
        progress(summary.results.count, items.count, "")
        return summary
    }
}
