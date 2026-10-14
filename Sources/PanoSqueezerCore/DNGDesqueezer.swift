import Foundation

/// Result of one successful desqueeze.
public struct DesqueezeOutcome: Sendable {
    public var output: URL
    public var rawIFDPath: String
    public var pointerOffset: UInt64
    public var appendedBytes: UInt64
}

/// Writes a desqueezed copy of a DNG using the append strategy:
///  1. clone the original to `.<name>.partial`
///  2. append the DefaultScale value and a new copy of the raw IFD at the end of the file
///  3. redirect the single 4-byte pointer that pointed to the old raw IFD to the new one
///  4. verify, copy dates, atomically rename to the final name
/// No existing byte is moved, so absolute offsets (e.g. in maker notes) stay valid.
public enum DNGDesqueezer {

    public static func desqueeze(source: URL, destination: URL, settings: DesqueezeSettings,
                                 isCancelled: () -> Bool = { false }) throws -> DesqueezeOutcome {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { throw DNGError.destinationExists }

        // --- Analyse the original (read-only) ---
        let structure = try TIFFStructure.parse(url: source)
        let raw = try structure.rawIFD()
        let order = structure.byteOrder
        if let existing = try TIFFStructure.defaultScale(of: raw, url: source, order: order),
           !existing.allSatisfy({ $0.isOne }) {
            throw DNGError.alreadyDesqueezed("\(existing[0]) × \(existing[1])")
        }

        // --- Build the bytes to append ---
        let originalSize = structure.fileSize
        let padding: UInt64 = originalSize % 2  // keep everything word aligned
        let valueOffset = originalSize + padding
        let newIFDOffset = valueOffset + 16
        var appended = [UInt8](repeating: 0, count: Int(padding))
        for r in settings.defaultScale {
            appended += order.bytes(r.numerator) + order.bytes(r.denominator)
        }
        appended += buildIFD(from: raw, defaultScaleValueOffset: UInt32(valueOffset), order: order)
        guard originalSize + UInt64(appended.count) < 1 << 32 else { throw DNGError.fileTooLarge }
        if isCancelled() { throw DNGError.cancelled }

        // --- Write ---
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent("." + destination.lastPathComponent + ".partial")
        try? fm.removeItem(at: partial)  // stale leftover from an earlier crash (always ours)
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // On APFS this is usually a clone: instant and nearly free.
            try fm.copyItem(at: source, to: partial)
            // The copy inherits permissions; originals from cameras/SD cards may be read-only.
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: partial.path)
        } catch {
            try? fm.removeItem(at: partial)
            throw DNGError.io(error.localizedDescription)
        }

        do {
            try appendAndPatch(file: partial, expectedSize: originalSize, appended: appended,
                               pointerOffset: raw.pointer.fileOffset, oldIFDOffset: UInt32(raw.offset),
                               newIFDOffset: UInt32(newIFDOffset), order: order)
            if isCancelled() { throw DNGError.cancelled }

            try OutputVerifier.verify(original: source, output: partial,
                                      pointerOffset: raw.pointer.fileOffset,
                                      expectedSize: originalSize + UInt64(appended.count),
                                      expectedDefaultScale: settings.defaultScale,
                                      isCancelled: isCancelled)

            try copyDates(from: source, to: partial)
            if fm.fileExists(atPath: destination.path) { throw DNGError.destinationExists }
            do {
                try fm.moveItem(at: partial, to: destination)
            } catch {
                throw DNGError.io(error.localizedDescription)
            }
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
        return DesqueezeOutcome(output: destination, rawIFDPath: raw.path,
                                pointerOffset: raw.pointer.fileOffset, appendedBytes: UInt64(appended.count))
    }

    /// New IFD: all raw IFD entries unchanged (their offsets still point to the original data),
    /// plus DefaultScale (replacing an existing 1/1 one), sorted by tag, same next-IFD offset.
    static func buildIFD(from raw: IFD, defaultScaleValueOffset: UInt32, order: ByteOrder) -> [UInt8] {
        var entries = raw.entries.filter { $0.tag != TIFFTag.defaultScale }
        entries.append(IFDEntry(tag: TIFFTag.defaultScale, type: TIFFType.rational, count: 2,
                                valueField: order.bytes(defaultScaleValueOffset), entryOffset: 0))
        entries.sort { $0.tag < $1.tag }  // TIFF requires ascending tag order

        var out = order.bytes(UInt16(entries.count))
        for e in entries {
            out += order.bytes(e.tag) + order.bytes(e.type) + order.bytes(e.count) + e.valueField
        }
        out += order.bytes(raw.nextIFDOffset)
        return out
    }

    private static func appendAndPatch(file: URL, expectedSize: UInt64, appended: [UInt8],
                                       pointerOffset: UInt64, oldIFDOffset: UInt32, newIFDOffset: UInt32,
                                       order: ByteOrder) throws {
        let handle: FileHandle
        do { handle = try FileHandle(forUpdating: file) } catch { throw DNGError.io(error.localizedDescription) }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            guard end == expectedSize else { throw DNGError.io("copy has unexpected size") }
            try handle.write(contentsOf: Data(appended))

            // Sanity check: the pointer must currently point to the old raw IFD.
            try handle.seek(toOffset: pointerOffset)
            let current = [UInt8](try handle.read(upToCount: 4) ?? Data())
            guard current.count == 4, order.u32(current, 0) == oldIFDOffset else {
                throw DNGError.io("unexpected pointer value")
            }
            // The only modification of existing bytes: exactly 4 bytes.
            try handle.seek(toOffset: pointerOffset)
            try handle.write(contentsOf: Data(order.bytes(newIFDOffset)))
            try handle.synchronize()
        } catch let e as DNGError {
            throw e
        } catch {
            throw DNGError.io(error.localizedDescription)
        }
    }

    private static func copyDates(from source: URL, to target: URL) throws {
        let fm = FileManager.default
        let attrs = (try? fm.attributesOfItem(atPath: source.path)) ?? [:]
        if let modified = attrs[.modificationDate] as? Date {
            do { try fm.setAttributes([.modificationDate: modified], ofItemAtPath: target.path) }
            catch { throw DNGError.io(error.localizedDescription) }
        }
        // Creation date can only be set on macOS; ignore failures elsewhere.
        if let created = attrs[.creationDate] as? Date {
            try? fm.setAttributes([.creationDate: created], ofItemAtPath: target.path)
        }
    }
}
