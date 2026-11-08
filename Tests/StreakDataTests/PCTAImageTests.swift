import Foundation
import StreakData
import XCTest

final class PCTAImageTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Builds a PC-TA file: a 256-byte header and signed 16-bit little-endian
    /// pixels, padded with `paddingRows` empty rows as the real files are.
    private func pcta(width: Int, height: Int, values: [Int16], paddingRows: Int = 1,
                      date: (day: UInt8, month: UInt8, year: UInt16)? = nil,
                      time: [UInt8] = [0, 0, 0, 0]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 256)
        if let date {
            bytes[0x96] = date.day
            bytes[0x97] = date.month
            bytes[0x98] = UInt8(date.year & 0xFF)
            bytes[0x99] = UInt8(date.year >> 8)
            bytes.replaceSubrange(0x9A..<0x9E, with: time)
        }
        bytes[0xA8] = UInt8(width - 1)
        bytes[0xAA] = UInt8(height - 1)
        for value in values + [Int16](repeating: 0, count: width * paddingRows) {
            let bits = UInt16(bitPattern: value)
            bytes += [UInt8(bits & 0xFF), UInt8(bits >> 8)]
        }
        return Data(bytes)
    }

    private func write(_ data: Data, extension suffix: String = "img") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        try data.write(to: url)
        return url
    }

    func testReadsSignedPixelsAndIgnoresPadding() throws {
        let url = try write(pcta(width: 3, height: 2, values: [-19, 0, 4095, 1, 2, 3],
                                 paddingRows: 2))
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try PixelImage(contentsOf: url)
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.bitDepth, 12)
        XCTAssertFalse(image.isColor)
        XCTAssertEqual(image.formatName, "PC-TA image")
        XCTAssertEqual(try image.row(0), [-19, 0, 4095])
        XCTAssertEqual(try image.row(1), [1, 2, 3])
    }

    func testExtensionIsCaseInsensitive() throws {
        let url = try write(pcta(width: 2, height: 2, values: [1, 2, 3, 4]), extension: "IMG")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try PixelImage(contentsOf: url).row(1), [3, 4])
    }

    func testHeaderTimestamp() throws {
        let dated = try write(pcta(width: 2, height: 2, values: [0, 0, 0, 0],
                                   date: (12, 10, 1998), time: [11, 3, 38, 56]))
        let blank = try write(pcta(width: 2, height: 2, values: [0, 0, 0, 0]))
        defer {
            try? FileManager.default.removeItem(at: dated)
            try? FileManager.default.removeItem(at: blank)
        }
        let timestamp = try XCTUnwrap(try PixelImage(contentsOf: dated).headerTimestamp)
        XCTAssertEqual([timestamp.year, timestamp.month, timestamp.day], [1998, 10, 12])
        XCTAssertEqual([timestamp.hour, timestamp.minute, timestamp.second], [11, 3, 38])
        XCTAssertEqual(timestamp.nanosecond, 560_000_000)
        XCTAssertNil(try PixelImage(contentsOf: blank).headerTimestamp)
    }

    func testExportKeepsNegativeValues() throws {
        let url = try write(pcta(width: 3, height: 1, values: [-19, 7, 4095]))
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: output)
        }
        try PixelImage(contentsOf: url).save(row: 0, to: output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "0\t-19\n1\t7\n2\t4095\n")
    }

    func testRejectsTruncatedAndInconsistentFiles() throws {
        let short = try write(Data(count: 100))
        let blankHeader = try write(Data(count: 256 + 2 * 512))
        // Header says 4 × 4 but only 2 rows of pixels follow.
        var mismatched = pcta(width: 4, height: 2, values: [Int16](repeating: 0, count: 8),
                              paddingRows: 0)
        mismatched[0xAA] = 3
        let inconsistent = try write(mismatched)
        defer {
            try? FileManager.default.removeItem(at: short)
            try? FileManager.default.removeItem(at: blankHeader)
            try? FileManager.default.removeItem(at: inconsistent)
        }
        for url in [short, blankHeader, inconsistent] {
            XCTAssertThrowsError(try PixelImage(contentsOf: url)) { error in
                guard case ImageError.invalidPCTA = error else {
                    return XCTFail("Expected a PC-TA error, got \(error)")
                }
            }
        }
    }

    /// The 1998 measurement and its TATOTIFF conversion: every TIFF pixel equals
    /// max(0, ⌊value · 255 / 4096⌋) of the raw data.
    func testProvidedSampleMatchesItsTIFFConversion() throws {
        let raw = root.appendingPathComponent("docs/examples/12OKTR2.IMG")
        let tiff = root.appendingPathComponent("docs/examples/12OKTR2.TIF")
        guard FileManager.default.fileExists(atPath: raw.path),
              FileManager.default.fileExists(atPath: tiff.path) else {
            throw XCTSkip("The local example files are not included in version control.")
        }
        let image = try PixelImage(contentsOf: raw)
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 480)
        XCTAssertEqual(image.values.min(), -19)
        XCTAssertEqual(image.values.max(), 3166)
        let timestamp = try XCTUnwrap(image.headerTimestamp)
        XCTAssertEqual([timestamp.year, timestamp.month, timestamp.day], [1998, 10, 12])

        let converted = try PixelImage(contentsOf: tiff)
        var mismatches = 0
        for (value, eightBit) in zip(image.values, converted.values) {
            let expected = max(0, (Int(value) * 255) >> 12)
            if Double(expected) != eightBit { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0)
    }
}
