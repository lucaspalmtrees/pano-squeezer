#if os(macOS)
import AppKit
import Foundation
import PanoSqueezerCore

/// Thread-safe cancel flag shared with the background conversion.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

/// State of the main window. All work (scanning, converting) runs in the background.
@MainActor
final class ConverterModel: ObservableObject {
    struct Progress: Equatable {
        var done = 0
        var total = 0
        var currentFile = ""
    }

    @Published private(set) var inputs: [URL] = []
    @Published private(set) var scan: ScanResult?
    @Published private(set) var isScanning = false
    @Published private(set) var isConverting = false
    @Published private(set) var progress = Progress()
    @Published private(set) var summary: BatchSummary?
    @Published var includeSubfolders = false {
        didSet { if oldValue != includeSubfolders { rescan() } }
    }

    private var cancelFlag: CancelFlag?
    private var scanGeneration = 0

    var canConvert: Bool { !isConverting && !isScanning && !(scan?.items.isEmpty ?? true) }

    // MARK: Input

    func setInputs(_ urls: [URL]) {
        guard !isConverting else { return }
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return }
        inputs = files
        summary = nil
        rescan()
    }

    func clear() {
        guard !isConverting else { return }
        inputs = []
        scan = nil
        summary = nil
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder or DNG files"
        if panel.runModal() == .OK { setInputs(panel.urls) }
    }

    private func rescan() {
        guard !inputs.isEmpty else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let urls = inputs
        let recursive = includeSubfolders
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = DNGScanner.scan(urls, includeSubfolders: recursive)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.scanGeneration else { return }
                    self.scan = result
                    self.isScanning = false
                }
            }
        }
    }

    // MARK: Conversion

    func convert(settings: DesqueezeSettings, destination: OutputDestination) {
        guard canConvert, let items = scan?.items else { return }
        let flag = CancelFlag()
        cancelFlag = flag
        summary = nil
        isConverting = true
        progress = Progress(done: 0, total: items.count, currentFile: "")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BatchConverter.run(
                items: items, settings: settings, destination: destination,
                progress: { done, total, name in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.progress = Progress(done: done, total: total, currentFile: name)
                        }
                    }
                },
                isCancelled: { flag.isCancelled })
            // Same serial main queue as the progress updates, so this always arrives last.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.summary = result
                    self.isConverting = false
                    self.cancelFlag = nil
                }
            }
        }
    }

    func cancel() {
        cancelFlag?.cancel()
    }

    func showInFinder() {
        guard let summary else { return }
        let folders = summary.outputFolders
        if folders.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(inputs)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(folders)
        }
    }
}
#endif
