import XCTest
@testable import PanoSqueezerCore

final class ParserTests: XCTestCase {

    func testFindsRawIFDInAllLayoutsAndByteOrders() throws {
        let cases: [(TestDNGBuilder.RawLocation, String, PointerLocation.Kind)] = [
            (.ifd0, "IFD0", .header),
            (.subIFD, "IFD0/SubIFD0", .subIFDEntry),
            (.subIFDArray, "IFD0/SubIFD1", .subIFDArray(1)),
        ]
        for order in [ByteOrder.little, .big] {
            for (location, path, kind) in cases {
                let tmp = TempDir()
                let url = tmp.write(TestDNGBuilder(order: order, rawLocation: location).build(), "a.dng")
                let s = try TIFFStructure.parse(url: url)
                XCTAssertEqual(s.byteOrder, order)
                let raw = try s.rawIFD()
                XCTAssertEqual(raw.path, path, "\(order) \(location)")
                XCTAssertEqual(raw.pointer.kind, kind)
                XCTAssertEqual(raw.entry(0x0100)?.valueField, order.bytes(UInt32(16)))
            }
        }
    }

    func testReadsDefaultScale() throws {
        let tmp = TempDir()
        let url = tmp.write(TestDNGBuilder(scale: .value(3, 2)).build(), "a.dng")
        let s = try TIFFStructure.parse(url: url)
        let scale = try TIFFStructure.defaultScale(of: try s.rawIFD(), url: url, order: s.byteOrder)
        XCTAssertEqual(scale, [Rational(3, 2), Rational(1, 1)])
    }

    func testMultipleRawIFDs() throws {
        let tmp = TempDir()
        let url = tmp.write(TestDNGBuilder(duplicateRaw: true).build(), "a.dng")
        XCTAssertThrowsError(try TIFFStructure.parse(url: url).rawIFD()) {
            XCTAssertEqual($0 as? DNGError, .multipleRawIFDs(2))
        }
    }

    // MARK: Damaged files

    func testNotTIFF() {
        let tmp = TempDir()
        let url = tmp.write(Data("hello world, not a tiff".utf8), "a.dng")
        XCTAssertThrowsError(try TIFFStructure.parse(url: url)) { XCTAssertEqual($0 as? DNGError, .notTIFF) }
    }

    func testBigTIFFRejected() {
        let tmp = TempDir()
        let url = tmp.write(Data([0x49, 0x49, 43, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "a.dng")
        XCTAssertThrowsError(try TIFFStructure.parse(url: url)) { XCTAssertEqual($0 as? DNGError, .bigTIFF) }
    }

    func testIFDOffsetOutOfBounds() {
        let tmp = TempDir()
        let url = tmp.write(Data([0x49, 0x49, 42, 0, 0xFF, 0xFF, 0, 0]), "a.dng")
        XCTAssertThrowsError(try TIFFStructure.parse(url: url)) {
            guard case .offsetOutOfBounds = $0 as? DNGError else { return XCTFail("\($0)") }
        }
    }

    func testCycleDetected() throws {
        // IFD0 whose next-IFD pointer points to itself.
        var b: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0]
        b += [1, 0] + [0xFE, 0, 4, 0, 1, 0, 0, 0, 0, 0, 0, 0] + [8, 0, 0, 0]
        let tmp = TempDir()
        let url = tmp.write(Data(b), "a.dng")
        XCTAssertThrowsError(try TIFFStructure.parse(url: url)) { XCTAssertEqual($0 as? DNGError, .cycle) }
    }

    func testSubIFDCycleDetected() throws {
        // IFD0 with a SubIFDs entry that points back to IFD0.
        var b: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0]
        b += [1, 0] + [0x4A, 0x01, 4, 0, 1, 0, 0, 0, 8, 0, 0, 0] + [0, 0, 0, 0]
        let tmp = TempDir()
        let url = tmp.write(Data(b), "a.dng")
        XCTAssertThrowsError(try TIFFStructure.parse(url: url)) { XCTAssertEqual($0 as? DNGError, .cycle) }
    }

    func testTruncatedFilesNeverCrash() throws {
        let full = TestDNGBuilder(rawLocation: .subIFDArray).build()
        let tmp = TempDir()
        for length in 0..<full.count - 3 {  // the last 3 bytes are padding, not structure
            let url = tmp.write(full.prefix(length), "t\(length).dng")
            XCTAssertThrowsError(try TIFFStructure.parse(url: url).rawIFD(), "length \(length)")
        }
    }

    func testRandomCorruptionNeverCrashes() throws {
        let full = [UInt8](TestDNGBuilder(rawLocation: .subIFDArray).build())
        var rng = SystemRandomNumberGenerator()
        let tmp = TempDir()
        for i in 0..<500 {
            var bytes = full
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
            }
            let url = tmp.write(Data(bytes), "c\(i).dng")
            _ = try? TIFFStructure.parse(url: url).rawIFD()  // must just not crash
        }
    }
}

final class WriterTests: XCTestCase {
    let settings = DesqueezeSettings(factor: try! SqueezeFactor(parsing: "1.33"), direction: .horizontal)

    func testDesqueezeAllLayoutsKeepsBytesAndSetsTag() throws {
        for order in [ByteOrder.little, .big] {
            for location in [TestDNGBuilder.RawLocation.ifd0, .subIFD, .subIFDArray] {
                for scale in [TestDNGBuilder.Scale.none, .one] {
                    let tmp = TempDir()
                    let original = TestDNGBuilder(order: order, rawLocation: location, scale: scale).build()
                    let src = tmp.write(original, "L1000123.DNG")
                    let past = Date(timeIntervalSince1970: 1_600_000_000)
                    try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: src.path)
                    let dst = tmp.url.appendingPathComponent("out/L1000123.DNG")

                    let outcome = try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings)

                    // Original untouched.
                    XCTAssertEqual(try Data(contentsOf: src), original)
                    // Output = original (except 4 pointer bytes) + appended data.
                    let out = try Data(contentsOf: dst)
                    XCTAssertEqual(UInt64(out.count), UInt64(original.count) + outcome.appendedBytes)
                    var diff: [Int] = []
                    for i in 0..<original.count where original[i] != out[i] { diff.append(i) }
                    let p = Int(outcome.pointerOffset)
                    XCTAssertTrue(diff.allSatisfy { (p..<p + 4).contains($0) }, "\(order) \(location) \(diff)")
                    XCTAssertFalse(diff.isEmpty)

                    // Tag present with the right value, in the raw IFD.
                    let s = try TIFFStructure.parse(url: dst)
                    let raw = try s.rawIFD()
                    XCTAssertEqual(try TIFFStructure.defaultScale(of: raw, url: dst, order: order),
                                   [Rational(133, 100), Rational(1, 1)])
                    XCTAssertEqual(raw.entries.map(\.tag), raw.entries.map(\.tag).sorted())
                    XCTAssertEqual(raw.offset % 2, 0)
                    // Dates copied, no leftovers.
                    let attrs = try FileManager.default.attributesOfItem(atPath: dst.path)
                    XCTAssertEqual(attrs[.modificationDate] as? Date, past)
                    let leftovers = try FileManager.default.contentsOfDirectory(atPath: dst.deletingLastPathComponent().path)
                    XCTAssertEqual(leftovers, ["L1000123.DNG"])
                }
            }
        }
    }

    func testVerticalAndReducedFractions() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder().build(), "a.dng")
        let dst = tmp.url.appendingPathComponent("o/a.dng")
        let s = DesqueezeSettings(factor: try SqueezeFactor(parsing: "1,5"), direction: .vertical)
        _ = try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: s)
        let st = try TIFFStructure.parse(url: dst)
        XCTAssertEqual(try TIFFStructure.defaultScale(of: try st.rawIFD(), url: dst, order: .little),
                       [Rational(1, 1), Rational(3, 2)])
    }

    func testReadOnlyOriginalWorks() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder().build(), "a.dng")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: src.path)
        let dst = tmp.url.appendingPathComponent("o/a.dng")
        _ = try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))
    }

    func testAlreadyDesqueezedIsSkipped() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder(scale: .value(3, 2)).build(), "a.dng")
        let dst = tmp.url.appendingPathComponent("o/a.dng")
        XCTAssertThrowsError(try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings)) {
            XCTAssertEqual($0 as? DNGError, .alreadyDesqueezed("1.5 × 1"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.url.appendingPathComponent("o").path))
    }

    func testNeverOverwrites() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder().build(), "a.dng")
        let dst = tmp.write(Data("existing".utf8), "o/a.dng")
        XCTAssertThrowsError(try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings)) {
            XCTAssertEqual($0 as? DNGError, .destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: dst), Data("existing".utf8))
    }

    func testCancelRemovesPartial() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder().build(), "a.dng")
        let dst = tmp.url.appendingPathComponent("o/a.dng")
        var calls = 0
        XCTAssertThrowsError(try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings,
                                                         isCancelled: { calls += 1; return calls > 1 })) {
            XCTAssertEqual($0 as? DNGError, .cancelled)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.url.appendingPathComponent("o").path), [])
    }

    // MARK: Verifier catches tampering

    func testVerifierDetectsChangedImageByte() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder().build(), "a.dng")
        let dst = tmp.url.appendingPathComponent("o/a.dng")
        let outcome = try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings)
        var bytes = [UInt8](try Data(contentsOf: dst))
        let expectedSize = UInt64(bytes.count)
        try OutputVerifier.verify(original: src, output: dst, pointerOffset: outcome.pointerOffset,
                                  expectedSize: expectedSize, expectedDefaultScale: settings.defaultScale)
        bytes[20] ^= 0xFF  // inside the "image data"
        try Data(bytes).write(to: dst)
        XCTAssertThrowsError(try OutputVerifier.verify(original: src, output: dst, pointerOffset: outcome.pointerOffset,
                                                       expectedSize: expectedSize,
                                                       expectedDefaultScale: settings.defaultScale)) {
            guard case .verificationFailed = $0 as? DNGError else { return XCTFail("\($0)") }
        }
    }

    func testVerifierDetectsWrongScaleAndSize() throws {
        let tmp = TempDir()
        let src = tmp.write(TestDNGBuilder(rawLocation: .subIFD).build(), "a.dng")
        let dst = tmp.url.appendingPathComponent("o/a.dng")
        let outcome = try DNGDesqueezer.desqueeze(source: src, destination: dst, settings: settings)
        let size = try FileManager.default.attributesOfItem(atPath: dst.path)[.size] as! UInt64
        XCTAssertThrowsError(try OutputVerifier.verify(original: src, output: dst, pointerOffset: outcome.pointerOffset,
                                                       expectedSize: size, expectedDefaultScale: [Rational(2, 1), Rational(1, 1)]))
        XCTAssertThrowsError(try OutputVerifier.verify(original: src, output: dst, pointerOffset: outcome.pointerOffset,
                                                       expectedSize: size + 1, expectedDefaultScale: settings.defaultScale))
    }
}

final class FactorTests: XCTestCase {
    func testParsing() throws {
        XCTAssertEqual(try SqueezeFactor(parsing: "1.33").hundredths, 133)
        XCTAssertEqual(try SqueezeFactor(parsing: "1,5").hundredths, 150)
        XCTAssertEqual(try SqueezeFactor(parsing: "2").hundredths, 200)
        XCTAssertEqual(try SqueezeFactor(parsing: " 1.8x ").hundredths, 180)
        XCTAssertEqual(try SqueezeFactor(parsing: "1.01").hundredths, 101)
        XCTAssertEqual(try SqueezeFactor(parsing: "4.00").hundredths, 400)
        XCTAssertEqual(try SqueezeFactor(parsing: "4").hundredths, 400)
    }

    func testErrors() {
        func err(_ s: String) -> FactorError? {
            do { _ = try SqueezeFactor(parsing: s); return nil } catch { return error as? FactorError }
        }
        XCTAssertEqual(err(""), .empty)
        XCTAssertEqual(err("1.00"), .outOfRange)
        XCTAssertEqual(err("1"), .outOfRange)
        XCTAssertEqual(err("4.01"), .outOfRange)
        XCTAssertEqual(err("0.5"), .outOfRange)
        XCTAssertEqual(err("1.333"), .tooManyDecimals)
        XCTAssertEqual(err("abc"), .invalidFormat)
        XCTAssertEqual(err("1.2.3"), .invalidFormat)
        XCTAssertEqual(err("-1.5"), .invalidFormat)
        XCTAssertEqual(err(".5"), .invalidFormat)
        XCTAssertEqual(err("1."), .invalidFormat)
        XCTAssertEqual(err("1e2"), .invalidFormat)
    }

    func testFractionsAndLabels() throws {
        func f(_ s: String) throws -> SqueezeFactor { try SqueezeFactor(parsing: s) }
        XCTAssertTrue(try f("1.33").fraction == (133, 100))
        XCTAssertTrue(try f("1.5").fraction == (3, 2))
        XCTAssertTrue(try f("2.0").fraction == (2, 1))
        XCTAssertTrue(try f("1.25").fraction == (5, 4))
        XCTAssertTrue(try f("1.6").fraction == (8, 5))
        XCTAssertEqual(try f("2").label, "2.0")
        XCTAssertEqual(try f("1.5").label, "1.5")
        XCTAssertEqual(try f("1.33").label, "1.33")
        XCTAssertEqual(try f("1.05").label, "1.05")
        XCTAssertEqual(SqueezeFactor.presets.map(\.label), ["1.25", "1.33", "1.5", "1.6", "1.8", "2.0"])
    }

    func testFolderNames() throws {
        XCTAssertEqual(DesqueezeSettings(factor: .standard, direction: .horizontal).outputFolderName, "Desqueezed 1.33x")
        XCTAssertEqual(DesqueezeSettings(factor: .standard, direction: .vertical).outputFolderName, "Desqueezed 1.33x vertical")
    }
}

final class ScanAndBatchTests: XCTestCase {
    func testScanFiltersFiles() throws {
        let tmp = TempDir()
        let dng = TestDNGBuilder().build()
        tmp.write(dng, "card/L1000001.DNG")
        tmp.write(dng, "card/L1000002.dng")
        tmp.write(dng, "card/._L1000001.DNG")            // macOS AppleDouble file
        tmp.write(dng, "card/.hidden.dng")
        tmp.write(Data("x".utf8), "card/notes.txt")
        tmp.write(Data("not tiff".utf8), "card/fake.DNG")
        tmp.write(dng, "card/sub/L1000003.DNG")
        tmp.write(dng, "card/Desqueezed 1.33x/L1000001.DNG")  // earlier output

        let flat = DNGScanner.scan([tmp.url.appendingPathComponent("card")], includeSubfolders: false)
        XCTAssertEqual(flat.items.map { $0.source.lastPathComponent }, ["L1000001.DNG", "L1000002.dng"])
        XCTAssertEqual(flat.ignoredCount, 2)
        XCTAssertEqual(flat.displayName, "card")

        let deep = DNGScanner.scan([tmp.url.appendingPathComponent("card")], includeSubfolders: true)
        XCTAssertEqual(deep.items.count, 3)
        XCTAssertEqual(deep.items.last?.relativeDirectory, "sub")
    }

    func testBatchMirrorsStructureAndSummarises() throws {
        let tmp = TempDir()
        tmp.write(TestDNGBuilder().build(), "card/a.DNG")
        tmp.write(TestDNGBuilder(order: .big, rawLocation: .subIFD).build(), "card/sub/b.DNG")
        tmp.write(TestDNGBuilder(scale: .value(2, 1)).build(), "card/c.DNG")
        let card = tmp.url.appendingPathComponent("card")
        let scan = DNGScanner.scan([card], includeSubfolders: true)
        let settings = DesqueezeSettings(factor: .standard, direction: .horizontal)

        var progressCalls = 0
        let summary = BatchConverter.run(items: scan.items, settings: settings, destination: .sameFolder,
                                         progress: { _, _, _ in progressCalls += 1 })
        XCTAssertEqual(summary.text, "2 converted · 1 skipped · 0 failed")
        XCTAssertEqual(progressCalls, 4)
        let out = card.appendingPathComponent("Desqueezed 1.33x")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("a.DNG").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("sub/b.DNG").path))
        XCTAssertEqual(summary.outputFolders.map(\.lastPathComponent), ["Desqueezed 1.33x"])

        // Second run: everything is skipped, nothing overwritten; output folder not rescanned.
        let again = BatchConverter.run(items: DNGScanner.scan([card], includeSubfolders: true).items,
                                       settings: settings, destination: .sameFolder)
        XCTAssertEqual(again.text, "0 converted · 3 skipped · 0 failed")
        XCTAssertEqual(again.results.first?.reason, "output file already exists")
    }

    func testCustomDestination() throws {
        let tmp = TempDir()
        let file = tmp.write(TestDNGBuilder().build(), "card/a.DNG")
        let target = tmp.url.appendingPathComponent("target")
        let scan = DNGScanner.scan([file], includeSubfolders: false)
        let settings = DesqueezeSettings(factor: try SqueezeFactor(parsing: "2"), direction: .vertical)
        let summary = BatchConverter.run(items: scan.items, settings: settings, destination: .custom(target))
        XCTAssertEqual(summary.converted, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("Desqueezed 2.0x vertical/a.DNG").path))
    }
}
