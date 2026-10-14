#if os(macOS)
import AppKit
import PanoSqueezerCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = ConverterModel()

    /// Selected factor in hundredths (133 = 1.33×); 0 = custom.
    @AppStorage("factorChoice") private var factorChoice = SqueezeFactor.standard.hundredths
    @AppStorage("customFactor") private var customFactorText = "1.40"
    @AppStorage("direction") private var direction = SqueezeDirection.horizontal
    @AppStorage("useCustomDestination") private var useCustomDestination = false
    @AppStorage("customDestinationPath") private var customDestinationPath = ""

    @State private var isDropTargeted = false
    @State private var showDetails = false

    // MARK: Derived settings

    private var factorResult: Result<SqueezeFactor, FactorError> {
        if factorChoice != 0, let f = try? SqueezeFactor(hundredths: factorChoice) { return .success(f) }
        do { return .success(try SqueezeFactor(parsing: customFactorText)) } catch let e as FactorError {
            return .failure(e)
        } catch { return .failure(.invalidFormat) }
    }

    private var settings: DesqueezeSettings? {
        guard case .success(let f) = factorResult else { return nil }
        return DesqueezeSettings(factor: f, direction: direction)
    }

    private var destination: OutputDestination? {
        guard useCustomDestination else { return .sameFolder }
        guard !customDestinationPath.isEmpty else { return nil }
        return .custom(URL(fileURLWithPath: customDestinationPath, isDirectory: true))
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone
            Toggle("Include subfolders", isOn: $model.includeSubfolders)
                .disabled(model.isConverting)
            settingsGrid
                .disabled(model.isConverting)
            Divider()
            bottomArea
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 400, alignment: .top)
    }

    // MARK: Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            dropZoneContent
                .padding(12)
        }
        .frame(height: 130)
        .contentShape(Rectangle())
        .onTapGesture { if !model.isConverting { model.chooseInputs() } }
        .dropDestination(for: URL.self) { urls, _ in
            model.setInputs(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .help("Drop a folder or DNG files here, or click to choose")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Choose a folder or DNG files")
    }

    @ViewBuilder
    private var dropZoneContent: some View {
        if let scan = model.scan, !model.inputs.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: model.inputs.count == 1 && scan.items.count == 1 ? "photo" : "folder")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text(scan.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(scanDescription(scan))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if !model.isConverting {
                    Button { model.clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
        } else if model.isScanning {
            ProgressView().controlSize(.small)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop DNG files or a folder")
                    .font(.headline)
                Text("or click to choose")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func scanDescription(_ scan: ScanResult) -> String {
        let dngs = scan.items.count == 1 ? "1 DNG" : "\(scan.items.count) DNGs"
        guard scan.ignoredCount > 0 else { return dngs }
        return "\(dngs) · \(scan.ignoredCount) other file\(scan.ignoredCount == 1 ? "" : "s") ignored"
    }

    // MARK: Settings

    private var settingsGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Squeeze").gridColumnAlignment(.trailing)
                HStack(spacing: 8) {
                    Picker("Squeeze", selection: $factorChoice) {
                        ForEach(SqueezeFactor.presets, id: \.hundredths) { f in
                            Text("\(f.label)×").tag(f.hundredths)
                        }
                        Divider()
                        Text("Custom…").tag(0)
                    }
                    .labelsHidden()
                    .fixedSize()
                    if factorChoice == 0 {
                        TextField("1.40", text: $customFactorText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Text("×")
                    }
                }
            }
            if factorChoice == 0, case .failure(let error) = factorResult {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text(error.description).font(.caption).foregroundStyle(.red)
                }
            }
            GridRow {
                Text("Direction")
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Direction", selection: $direction) {
                        Text("Horizontal").tag(SqueezeDirection.horizontal)
                        Text("Vertical").tag(SqueezeDirection.vertical)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Vertical: lens mounted rotated by 90°")
                    Text("Portrait photos still use Horizontal – the lens turns with the camera.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GridRow {
                Text("Save to")
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Save to", selection: destinationSelection) {
                        Text("Same folder").tag(false)
                        Text("Choose…").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Text(destinationDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if useCustomDestination {
                        Button("Change…") { _ = chooseDestination() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// "Choose…" only becomes selected once a folder has actually been chosen.
    private var destinationSelection: Binding<Bool> {
        Binding(
            get: { useCustomDestination && !customDestinationPath.isEmpty },
            set: { wantsCustom in
                guard wantsCustom else { useCustomDestination = false; return }
                if FileManager.default.fileExists(atPath: customDestinationPath) {
                    useCustomDestination = true  // remembered folder still exists
                    return
                }
                // Open the panel after the segmented control has finished handling the click:
                // a modal panel started while the click is still being processed closes immediately.
                DispatchQueue.main.async {
                    if chooseDestination() { useCustomDestination = true }
                }
            })
    }

    private var destinationDescription: String {
        let folder = settings?.outputFolderName ?? "Desqueezed …"
        if useCustomDestination, !customDestinationPath.isEmpty {
            return "\((customDestinationPath as NSString).abbreviatingWithTildeInPath)/\(folder)"
        }
        return "Subfolder “\(folder)” next to the originals"
    }

    /// Returns true if a folder was chosen.
    private func chooseDestination() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where the converted copies are saved"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        customDestinationPath = url.path
        return true
    }

    // MARK: Convert / progress / result

    @ViewBuilder
    private var bottomArea: some View {
        if model.isConverting {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(model.progress.done), total: Double(max(model.progress.total, 1)))
                HStack {
                    Text("\(model.progress.done) / \(model.progress.total)")
                        .monospacedDigit()
                    Text(model.progress.currentFile)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
                .font(.callout)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = model.summary {
                    resultView(summary)
                }
                HStack {
                    Spacer()
                    Button {
                        if let settings, let destination {
                            model.convert(settings: settings, destination: destination)
                        }
                    } label: {
                        Text("Convert").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConvert || settings == nil || destination == nil)
                }
            }
        }
    }

    private func resultView(_ summary: BatchSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: summary.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(summary.failed > 0 ? Color.orange : Color.green)
                Text(summary.text + (summary.wasCancelled ? " · cancelled" : ""))
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Show in Finder") { model.showInFinder() }
                    .controlSize(.small)
            }
            let problems = summary.results.filter { $0.status != .converted }
            if !problems.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(problems) { r in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: r.status == .failed ? "xmark.circle" : "minus.circle")
                                        .foregroundStyle(r.status == .failed ? Color.red : Color.secondary)
                                    Text(r.source.lastPathComponent).fontWeight(.medium)
                                    Text(r.reason ?? "").foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                } label: {
                    Text("Details").font(.callout)
                }
            }
            if summary.converted > 0, let donation = AppInfo.donationURL {
                Link(destination: donation) {
                    Text("☕ Support this project")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
