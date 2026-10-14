import Foundation

// MARK: - Byte order helpers

public enum ByteOrder: Sendable, Equatable {
    case little  // "II"
    case big     // "MM"

    func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        switch self {
        case .little: return UInt16(b[i]) | UInt16(b[i + 1]) << 8
        case .big: return UInt16(b[i]) << 8 | UInt16(b[i + 1])
        }
    }

    func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        switch self {
        case .little:
            return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        case .big:
            return UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
        }
    }

    func bytes(_ v: UInt16) -> [UInt8] {
        let lo = UInt8(v & 0xFF), hi = UInt8(v >> 8)
        return self == .little ? [lo, hi] : [hi, lo]
    }

    func bytes(_ v: UInt32) -> [UInt8] {
        let b = [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
        return self == .little ? b : b.reversed()
    }
}

// MARK: - Tags and types

public enum TIFFTag {
    public static let newSubFileType: UInt16 = 0x00FE
    public static let subIFDs: UInt16 = 0x014A
    public static let defaultScale: UInt16 = 0xC61E  // 50718
}

public enum TIFFType {
    public static let short: UInt16 = 3
    public static let long: UInt16 = 4
    public static let rational: UInt16 = 5
    public static let ifd: UInt16 = 13

    /// Size in bytes of one value of the given TIFF field type (nil = unknown type).
    public static func size(of type: UInt16) -> UInt64? {
        switch type {
        case 1, 2, 6, 7: return 1         // BYTE, ASCII, SBYTE, UNDEFINED
        case 3, 8: return 2               // SHORT, SSHORT
        case 4, 9, 11, 13: return 4       // LONG, SLONG, FLOAT, IFD
        case 5, 10, 12: return 8          // RATIONAL, SRATIONAL, DOUBLE
        default: return nil
        }
    }
}

// MARK: - Read-only file access

/// Random-access, read-only reader. Only reads the bytes it is asked for; never loads the whole file.
final class FileReader {
    let handle: FileHandle
    let size: UInt64

    init(url: URL) throws {
        do {
            handle = try FileHandle(forReadingFrom: url)
            size = try handle.seekToEnd()
        } catch {
            throw DNGError.cannotOpen(error.localizedDescription)
        }
    }

    deinit { try? handle.close() }

    func read(at offset: UInt64, count: Int, what: String) throws -> [UInt8] {
        guard count >= 0, offset <= size, UInt64(count) <= size - offset else {
            throw DNGError.offsetOutOfBounds(what)
        }
        if count == 0 { return [] }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw DNGError.truncated(what) }
            return [UInt8](data)
        } catch let e as DNGError {
            throw e
        } catch {
            throw DNGError.truncated(what)
        }
    }
}

// MARK: - Structure

/// One 12-byte IFD entry exactly as stored in the file.
public struct IFDEntry: Equatable, Sendable {
    public var tag: UInt16
    public var type: UInt16
    public var count: UInt32
    /// The raw 4-byte value/offset field in file byte order.
    public var valueField: [UInt8]
    /// Absolute file position of this entry (0 for entries that were never written).
    public var entryOffset: UInt64

    /// Same content (ignores where the entry is stored).
    public func sameContent(as other: IFDEntry) -> Bool {
        tag == other.tag && type == other.type && count == other.count && valueField == other.valueField
    }

    /// Total value size in bytes, or nil for unknown types.
    var valueByteCount: UInt64? {
        TIFFType.size(of: type).map { $0 * UInt64(count) }
    }
}

/// Where the 4-byte pointer to an IFD is stored. This is the only thing the writer ever overwrites.
public struct PointerLocation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case header             // bytes 4–7 of the file
        case nextIFD            // "next IFD" field of the previous IFD in the chain
        case subIFDEntry        // value field of a SubIFDs entry with count 1
        case subIFDArray(Int)   // element i of an out-of-line SubIFDs array
    }
    public var kind: Kind
    public var fileOffset: UInt64
}

public struct IFD: Equatable, Sendable {
    public var offset: UInt64
    public var entries: [IFDEntry]
    public var nextIFDOffset: UInt32
    public var pointer: PointerLocation
    /// Human-readable position, e.g. "IFD0" or "IFD0/SubIFD1".
    public var path: String

    public func entry(_ tag: UInt16) -> IFDEntry? { entries.first { $0.tag == tag } }

    /// NewSubFileType value. A missing tag means 0 (TIFF default).
    public func newSubFileType(order: ByteOrder) -> UInt32 {
        guard let e = entry(TIFFTag.newSubFileType), e.count == 1 else { return 0 }
        switch e.type {
        case TIFFType.short: return UInt32(order.u16(e.valueField, 0))
        case TIFFType.long: return order.u32(e.valueField, 0)
        default: return 0
        }
    }
}

public struct Rational: Equatable, Sendable, CustomStringConvertible {
    public var numerator: UInt32
    public var denominator: UInt32
    public init(_ n: UInt32, _ d: UInt32) { numerator = n; denominator = d }
    public var isOne: Bool { numerator != 0 && numerator == denominator }
    public var description: String {
        guard denominator != 0 else { return "\(numerator)/0" }
        if numerator % denominator == 0 { return "\(numerator / denominator)" }
        var s = String(format: "%.2f", Double(numerator) / Double(denominator))
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}

/// Parsed TIFF/DNG structure: header and all IFDs reachable via the IFD chain and SubIFDs.
/// EXIF/GPS IFDs are not followed (not needed).
public struct TIFFStructure: Sendable {
    public var byteOrder: ByteOrder
    public var fileSize: UInt64
    public var ifds: [IFD]

    // Limits against damaged/hostile files.
    static let maxIFDs = 256
    static let maxEntries = 1000
    static let maxDepth = 8
    static let maxSubIFDs = 64

    /// Parse only the header and IFDs of the file (opened read-only).
    public static func parse(url: URL) throws -> TIFFStructure {
        let reader = try FileReader(url: url)
        return try parse(reader: reader)
    }

    static func parse(reader: FileReader) throws -> TIFFStructure {
        let header = try reader.read(at: 0, count: 8, what: "header")
        let order: ByteOrder
        switch (header[0], header[1]) {
        case (0x49, 0x49): order = .little
        case (0x4D, 0x4D): order = .big
        default: throw DNGError.notTIFF
        }
        let magic = order.u16(header, 2)
        if magic == 43 { throw DNGError.bigTIFF }
        guard magic == 42 else { throw DNGError.notTIFF }
        if reader.size >= 1 << 32 { throw DNGError.fileTooLarge }

        var parser = Parser(reader: reader, order: order)
        let ifd0 = order.u32(header, 4)
        guard ifd0 != 0 else { throw DNGError.noRawIFD }
        try parser.parseChain(first: ifd0, pointer: PointerLocation(kind: .header, fileOffset: 4),
                              prefix: "", depth: 0)
        return TIFFStructure(byteOrder: order, fileSize: reader.size, ifds: parser.ifds)
    }

    /// IFDs that hold the main raw image (NewSubFileType == 0).
    public var rawIFDs: [IFD] { ifds.filter { $0.newSubFileType(order: byteOrder) == 0 } }

    /// The single raw IFD, or an error if there is none or more than one.
    public func rawIFD() throws -> IFD {
        let raws = rawIFDs
        if raws.isEmpty { throw DNGError.noRawIFD }
        if raws.count > 1 { throw DNGError.multipleRawIFDs(raws.count) }
        return raws[0]
    }

    /// Reads the DefaultScale tag of an IFD, if present. Throws if it has an unexpected format.
    public static func defaultScale(of ifd: IFD, url: URL, order: ByteOrder) throws -> [Rational]? {
        guard let e = ifd.entry(TIFFTag.defaultScale) else { return nil }
        guard e.type == TIFFType.rational, e.count == 2 else { throw DNGError.unexpectedDefaultScale }
        let reader = try FileReader(url: url)
        let offset = UInt64(order.u32(e.valueField, 0))
        let b = try reader.read(at: offset, count: 16, what: "DefaultScale value")
        return [Rational(order.u32(b, 0), order.u32(b, 4)), Rational(order.u32(b, 8), order.u32(b, 12))]
    }
}

private struct Parser {
    let reader: FileReader
    let order: ByteOrder
    var ifds: [IFD] = []
    var visited = Set<UInt64>()

    init(reader: FileReader, order: ByteOrder) {
        self.reader = reader
        self.order = order
    }

    /// Follows a chain of IFDs (via the "next IFD" field) starting at `first`.
    mutating func parseChain(first: UInt32, pointer: PointerLocation, prefix: String, depth: Int) throws {
        var offset = first
        var pointer = pointer
        var index = 0
        while offset != 0 {
            let name = prefix.isEmpty ? "IFD\(index)" : "\(prefix)\(index == 0 ? "" : "+\(index)")"
            let ifd = try parseIFD(at: UInt64(offset), pointer: pointer, path: name, depth: depth)
            // Pointer to the next IFD sits right after the entries.
            pointer = PointerLocation(kind: .nextIFD, fileOffset: ifd.offset + 2 + UInt64(ifd.entries.count) * 12)
            offset = ifd.nextIFDOffset
            index += 1
        }
    }

    mutating func parseIFD(at offset: UInt64, pointer: PointerLocation, path: String, depth: Int) throws -> IFD {
        guard depth <= TIFFStructure.maxDepth else { throw DNGError.tooManyIFDs }
        guard ifds.count < TIFFStructure.maxIFDs else { throw DNGError.tooManyIFDs }
        guard !visited.contains(offset) else { throw DNGError.cycle }
        visited.insert(offset)

        let countBytes = try reader.read(at: offset, count: 2, what: "\(path) entry count")
        let n = Int(order.u16(countBytes, 0))
        guard n > 0, n <= TIFFStructure.maxEntries else { throw DNGError.tooManyEntries(n) }
        // Layout: u16 count, n × 12-byte entries, u32 next-IFD offset.
        let body = try reader.read(at: offset + 2, count: n * 12 + 4, what: "\(path) entries")
        var entries: [IFDEntry] = []
        entries.reserveCapacity(n)
        for i in 0..<n {
            let p = i * 12
            entries.append(IFDEntry(tag: order.u16(body, p), type: order.u16(body, p + 2),
                                    count: order.u32(body, p + 4), valueField: Array(body[p + 8 ..< p + 12]),
                                    entryOffset: offset + 2 + UInt64(p)))
        }
        // Values larger than 4 bytes live elsewhere: make sure they are inside the file.
        for e in entries {
            if let size = e.valueByteCount, size > 4 {
                let valueOffset = UInt64(order.u32(e.valueField, 0))
                guard valueOffset <= reader.size, size <= reader.size - valueOffset else {
                    throw DNGError.offsetOutOfBounds("\(path) tag 0x\(String(e.tag, radix: 16))")
                }
            }
        }
        let ifd = IFD(offset: offset, entries: entries, nextIFDOffset: order.u32(body, n * 12),
                      pointer: pointer, path: path)
        ifds.append(ifd)

        // Follow SubIFDs (tag 0x014A, type LONG or IFD).
        if let sub = ifd.entry(TIFFTag.subIFDs), sub.type == TIFFType.long || sub.type == TIFFType.ifd {
            let count = Int(sub.count)
            guard count <= TIFFStructure.maxSubIFDs else { throw DNGError.tooManyIFDs }
            if count == 1 {
                // Single SubIFD: the offset is stored directly in the entry's value field.
                let target = order.u32(sub.valueField, 0)
                if target != 0 {
                    try parseChain(first: target,
                                   pointer: PointerLocation(kind: .subIFDEntry, fileOffset: sub.entryOffset + 8),
                                   prefix: "\(path)/SubIFD0", depth: depth + 1)
                }
            } else if count > 1 {
                // Several SubIFDs: the value field points to an array of offsets.
                let arrayOffset = UInt64(order.u32(sub.valueField, 0))
                let arr = try reader.read(at: arrayOffset, count: count * 4, what: "\(path) SubIFDs array")
                for i in 0..<count {
                    let target = order.u32(arr, i * 4)
                    if target == 0 { continue }
                    try parseChain(first: target,
                                   pointer: PointerLocation(kind: .subIFDArray(i), fileOffset: arrayOffset + UInt64(i * 4)),
                                   prefix: "\(path)/SubIFD\(i)", depth: depth + 1)
                }
            }
        }
        return ifd
    }
}
