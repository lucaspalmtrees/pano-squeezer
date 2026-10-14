import Foundation
import PanoSqueezerCore

// Test tool for the core logic:
//   pano-squeezer-cli --factor 1.33 [--vertical] [--recursive] [--out DIR] <files|folders…>
//   pano-squeezer-cli --info <file>      (print the IFD structure)

let usage = """
usage: pano-squeezer-cli --factor 1.33 [--vertical] [--recursive] [--out DIR] <files|folders…>
       pano-squeezer-cli --info <file.dng>

  --factor F     squeeze factor 1.01–4.00 (e.g. 1.33, 1,5, 2)
  --vertical     lens mounted rotated by 90° (stretch vertically)
  --recursive    include subfolders
  --out DIR      put the "Desqueezed …" folder into DIR (default: next to the originals)
  --info         print the TIFF/DNG structure of a file and exit
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var factorText: String?
var direction = SqueezeDirection.horizontal
var recursive = false
var outDir: URL?
var info = false
var inputs: [URL] = []

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--factor", "-f":
        guard let v = args.popFirst() else { fail("--factor needs a value\n\n" + usage) }
        factorText = v
    case "--vertical": direction = .vertical
    case "--recursive", "-r": recursive = true
    case "--out", "-o":
        guard let v = args.popFirst() else { fail("--out needs a directory\n\n" + usage) }
        outDir = URL(fileURLWithPath: v, isDirectory: true)
    case "--info": info = true
    case "--help", "-h": print(usage); exit(0)
    default:
        if arg.hasPrefix("-") { fail("unknown option \(arg)\n\n" + usage) }
        inputs.append(URL(fileURLWithPath: arg))
    }
}
guard !inputs.isEmpty else { fail(usage) }

if info {
    for url in inputs {
        do {
            let s = try TIFFStructure.parse(url: url)
            print("\(url.lastPathComponent): \(s.byteOrder == .little ? "little" : "big") endian, \(s.fileSize) bytes")
            for ifd in s.ifds {
                let nst = ifd.newSubFileType(order: s.byteOrder)
                var line = "  \(ifd.path) @\(ifd.offset): \(ifd.entries.count) entries, NewSubFileType=\(nst), pointer @\(ifd.pointer.fileOffset)"
                if let scale = try TIFFStructure.defaultScale(of: ifd, url: url, order: s.byteOrder) {
                    line += ", DefaultScale=\(scale[0]) × \(scale[1])"
                }
                print(line)
            }
            print("  raw IFD: \((try? s.rawIFD().path) ?? "none/ambiguous")")
        } catch {
            print("\(url.lastPathComponent): \(error)")
        }
    }
    exit(0)
}

guard let factorText else { fail("--factor is required\n\n" + usage) }
let factor: SqueezeFactor
do { factor = try SqueezeFactor(parsing: factorText) } catch { fail("invalid factor: \(error)") }

let settings = DesqueezeSettings(factor: factor, direction: direction)
let scan = DNGScanner.scan(inputs, includeSubfolders: recursive)
print("Found \(scan.items.count) DNG(s), ignored \(scan.ignoredCount) file(s).")

let summary = BatchConverter.run(items: scan.items, settings: settings,
                                 destination: outDir.map { .custom($0) } ?? .sameFolder)
for r in summary.results {
    switch r.status {
    case .converted: print("  ✓ \(r.source.lastPathComponent) → \(r.output.path)")
    case .skipped: print("  – \(r.source.lastPathComponent): skipped, \(r.reason ?? "")")
    case .failed: print("  ✗ \(r.source.lastPathComponent): failed, \(r.reason ?? "")")
    }
}
print(summary.text)
exit(summary.failed > 0 ? 1 : 0)
