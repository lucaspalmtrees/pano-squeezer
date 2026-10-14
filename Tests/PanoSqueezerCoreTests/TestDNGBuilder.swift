import Foundation
@testable import PanoSqueezerCore

/// Builds tiny synthetic TIFF/DNG files in memory for tests (never checked in).
struct TestDNGBuilder {
    enum RawLocation { case ifd0, subIFD, subIFDArray }
    enum Scale { case none, one, value(UInt32, UInt32) }

    var order: ByteOrder = .little
    var rawLocation: RawLocation = .ifd0
    var scale: Scale = .none
    /// Add a second IFD with NewSubFileType 0 (invalid: two raw images).
    var duplicateRaw = false

    struct Entry { var tag: UInt16; var type: UInt16; var count: UInt32; var data: [UInt8] }

    final class Blob {
        var bytes: [UInt8] = []
        let order: ByteOrder
        init(order: ByteOrder) { self.order = order }
        func align() { if bytes.count % 2 == 1 { bytes.append(0) } }
        @discardableResult func append(_ b: [UInt8]) -> UInt32 { align(); let o = bytes.count; bytes += b; return UInt32(o) }
        func patch32(at offset: Int, _ v: UInt32) { bytes.replaceSubrange(offset..<offset + 4, with: order.bytes(v)) }

        /// Writes out-of-line values, then the IFD. Returns (ifdOffset, nextFieldOffset).
        func writeIFD(_ entries: [Entry]) -> (UInt32, Int) {
            var fields: [[UInt8]] = []
            for e in entries {
                if e.data.count > 4 {
                    fields.append(order.bytes(append(e.data)))
                } else {
                    fields.append(e.data + [UInt8](repeating: 0, count: 4 - e.data.count))
                }
            }
            align()
            let ifdOffset = UInt32(bytes.count)
            bytes += order.bytes(UInt16(entries.count))
            let sortedIndices = entries.indices.sorted { entries[$0].tag < entries[$1].tag }
            for i in sortedIndices {
                let e = entries[i]
                bytes += order.bytes(e.tag) + order.bytes(e.type) + order.bytes(e.count) + fields[i]
            }
            let next = bytes.count
            bytes += order.bytes(UInt32(0))
            return (ifdOffset, next)
        }
    }

    func short(_ tag: UInt16, _ v: UInt16) -> Entry { Entry(tag: tag, type: 3, count: 1, data: order.bytes(v)) }
    func long(_ tag: UInt16, _ v: UInt32) -> Entry { Entry(tag: tag, type: 4, count: 1, data: order.bytes(v)) }
    func rationals(_ tag: UInt16, _ r: [(UInt32, UInt32)]) -> Entry {
        Entry(tag: tag, type: 5, count: UInt32(r.count), data: r.flatMap { order.bytes($0.0) + order.bytes($0.1) })
    }

    func rawEntries(stripOffset: UInt32) -> [Entry] {
        var e = [
            long(0x00FE, 0),                     // NewSubFileType = main image
            long(0x0100, 16), long(0x0101, 8),   // width, height
            short(0x0103, 1),                    // compression
            long(0x0111, stripOffset),           // StripOffsets → image data
            long(0x0117, 128),                   // StripByteCounts
            Entry(tag: 0xC620, type: 3, count: 2, data: order.bytes(UInt16(16)) + order.bytes(UInt16(8))), // DefaultCropSize
        ]
        switch scale {
        case .none: break
        case .one: e.append(rationals(TIFFTag.defaultScale, [(1, 1), (1, 1)]))
        case .value(let n, let d): e.append(rationals(TIFFTag.defaultScale, [(n, d), (1, 1)]))
        }
        return e
    }

    func previewEntries(stripOffset: UInt32) -> [Entry] {
        [long(0x00FE, 1), long(0x0100, 4), long(0x0101, 2), long(0x0111, stripOffset), long(0x0117, 32),
         Entry(tag: 0x010F, type: 2, count: 6, data: Array("Leica\0".utf8))]
    }

    func build() -> Data {
        let blob = Blob(order: order)
        blob.bytes = order == .little ? [0x49, 0x49, 42, 0] : [0x4D, 0x4D, 0, 42]
        blob.bytes += [0, 0, 0, 0]
        // "Image data" with a recognisable pattern.
        let imageData = blob.append((0..<128).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
        let previewData = blob.append([UInt8](repeating: 0xAB, count: 32))
        // Fake maker note with an absolute offset inside (must stay valid → nothing may move).
        let makerNote = Entry(tag: 0x927C, type: 7, count: 12, data: Array("LEICA\0\0\0".utf8) + order.bytes(imageData))

        switch rawLocation {
        case .ifd0:
            let (ifd1, _) = blob.writeIFD(previewEntries(stripOffset: previewData))
            var e = rawEntries(stripOffset: imageData)
            e.append(makerNote)
            let (ifd0, next) = blob.writeIFD(e)
            blob.patch32(at: next, ifd1)
            blob.patch32(at: 4, ifd0)
            if duplicateRaw {
                let (extra, _) = blob.writeIFD(rawEntries(stripOffset: imageData))
                blob.patch32(at: Int(ifd1) + 2 + previewEntries(stripOffset: 0).count * 12, extra)
            }
        case .subIFD:
            let (raw, _) = blob.writeIFD(rawEntries(stripOffset: imageData))
            var e = previewEntries(stripOffset: previewData)
            e.append(long(TIFFTag.subIFDs, raw))
            e.append(makerNote)
            let (ifd0, _) = blob.writeIFD(e)
            blob.patch32(at: 4, ifd0)
        case .subIFDArray:
            let (preview2, _) = blob.writeIFD(previewEntries(stripOffset: previewData))
            let (raw, _) = blob.writeIFD(rawEntries(stripOffset: imageData))
            var e = previewEntries(stripOffset: previewData)
            e.append(Entry(tag: TIFFTag.subIFDs, type: 13, count: 2, data: order.bytes(preview2) + order.bytes(raw)))
            e.append(makerNote)
            let (ifd0, _) = blob.writeIFD(e)
            blob.patch32(at: 4, ifd0)
        }
        // Some trailing bytes so the file size is odd (tests padding).
        blob.bytes += [1, 2, 3]
        return Data(blob.bytes)
    }
}

/// Temporary directory per test, removed afterwards.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("pano-tests-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ data: Data, _ name: String) -> URL {
        let u = url.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! data.write(to: u)
        return u
    }
}
