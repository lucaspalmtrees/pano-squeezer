import XCTest
@testable import PanoSqueezerCore

/// Writes synthetic sample DNGs to $PANO_SAMPLE_DIR (if set) so scripts/integration-test.sh
/// can also check them with exiftool. Does nothing otherwise.
final class SampleExport: XCTestCase {
    func testExportSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["PANO_SAMPLE_DIR"] else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for order in [ByteOrder.little, .big] {
            for location in [TestDNGBuilder.RawLocation.ifd0, .subIFD, .subIFDArray] {
                let name = "synthetic-\(order == .little ? "le" : "be")-\(location).dng"
                try TestDNGBuilder(order: order, rawLocation: location).build()
                    .write(to: base.appendingPathComponent(name))
            }
        }
    }
}
