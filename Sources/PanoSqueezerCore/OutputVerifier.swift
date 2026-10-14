import Foundation

/// Mandatory check after every write.
public enum OutputVerifier {
    static let chunkSize = 4 * 1024 * 1024

    /// Throws `DNGError.verificationFailed` if the output is not exactly
    /// "original + appended bytes, with only the 4 pointer bytes changed".
    public static func verify(original: URL, output: URL, pointerOffset: UInt64, expectedSize: UInt64,
                              expectedDefaultScale: [Rational], isCancelled: () -> Bool = { false }) throws {
        func fail(_ reason: String) -> DNGError { .verificationFailed(reason) }

        // 1. Structure: re-parse both files.
        let a: TIFFStructure, b: TIFFStructure
        do {
            a = try TIFFStructure.parse(url: original)
            b = try TIFFStructure.parse(url: output)
        } catch {
            throw fail("output cannot be parsed (\(error))")
        }
        guard b.fileSize == expectedSize else { throw fail("unexpected file size") }
        guard a.byteOrder == b.byteOrder, a.ifds.count == b.ifds.count else { throw fail("IFD structure differs") }
        let rawA = try a.rawIFD()
        let rawB: IFD
        do { rawB = try b.rawIFD() } catch { throw fail("raw IFD not found in output") }

        for (x, y) in zip(a.ifds, b.ifds) {
            guard x.path == y.path else { throw fail("IFD order differs") }
            if x.path == rawA.path {
                guard y.path == rawB.path, y.offset >= a.fileSize else { throw fail("raw IFD was not appended") }
                guard y.pointer.fileOffset == pointerOffset else { throw fail("wrong pointer changed") }
                let ex = x.entries.filter { $0.tag != TIFFTag.defaultScale }
                let ey = y.entries.filter { $0.tag != TIFFTag.defaultScale }
                guard ex.count == ey.count, zip(ex, ey).allSatisfy({ $0.sameContent(as: $1) }) else {
                    throw fail("raw IFD entries differ")
                }
                guard y.nextIFDOffset == x.nextIFDOffset else { throw fail("next IFD offset differs") }
            } else {
                // The redirected pointer may live in this IFD (SubIFDs value field or next-IFD field).
                let nextFieldOffset = x.offset + 2 + UInt64(x.entries.count) * 12
                var entriesMatch = x.entries.count == y.entries.count
                if entriesMatch {
                    for (ex, ey) in zip(x.entries, y.entries) where ex != ey {
                        let holdsPointer: Bool = ex.entryOffset + 8 == pointerOffset
                        var sameHeader: Bool = ex.entryOffset == ey.entryOffset && ex.tag == ey.tag
                        sameHeader = sameHeader && ex.type == ey.type && ex.count == ey.count
                        if !(holdsPointer && sameHeader) { entriesMatch = false }
                    }
                }
                let nextMatches: Bool = x.nextIFDOffset == y.nextIFDOffset || nextFieldOffset == pointerOffset
                guard x.offset == y.offset, entriesMatch, nextMatches else {
                    throw fail("\(x.path) differs")
                }
            }
        }
        let scale: [Rational]?
        do { scale = try TIFFStructure.defaultScale(of: rawB, url: output, order: b.byteOrder) }
        catch { throw fail("DefaultScale unreadable") }
        guard scale == expectedDefaultScale else { throw fail("DefaultScale has wrong value") }

        // 2. Bytes: output[0 ..< originalSize] == original, except the 4 pointer bytes.
        let ra = try FileReader(url: original)
        let rb = try FileReader(url: output)
        let pointerRange = pointerOffset ..< pointerOffset + 4
        var pos: UInt64 = 0
        while pos < a.fileSize {
            if isCancelled() { throw DNGError.cancelled }
            let n = Int(min(UInt64(chunkSize), a.fileSize - pos))
            var ca = try ra.read(at: pos, count: n, what: "original")
            var cb = try rb.read(at: pos, count: n, what: "output")
            // Mask the pointer bytes if they fall into this chunk.
            for p in pointerRange where p >= pos && p < pos + UInt64(n) {
                let i = Int(p - pos)
                ca[i] = 0
                cb[i] = 0
            }
            guard ca == cb else { throw fail("original bytes changed") }
            pos += UInt64(n)
        }
    }
}
