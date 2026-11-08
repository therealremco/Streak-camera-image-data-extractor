import CoreGraphics
import Foundation
import ImageIO
import StreakData
import UniformTypeIdentifiers
import XCTest

final class PixelImageTests: XCTestCase {
    private func image(
        _ bytes: [UInt8], width: Int = 3, height: Int = 2,
        bits: Int = 8, color: Bool = false, rowBytes: Int? = nil,
        order: CGBitmapInfo = []
    ) throws -> CGImage {
        let channels = color ? 3 : 1
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: bits,
            bitsPerPixel: bits * channels,
            bytesPerRow: rowBytes ?? width * channels * bits / 8,
            space: color ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
            bitmapInfo: order, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func temporaryURL(extension suffix: String = "tif") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(suffix)
    }

    private func writeTIFF(_ image: CGImage, to url: URL, pages: Int = 1) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, pages, nil)
        )
        for _ in 0..<pages {
            CGImageDestinationAddImage(destination, image, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testRowsAndPadding() throws {
        let pixels = try PixelImage(image: image([1, 2, 3, 255, 4, 5, 6, 255], rowBytes: 4))
        XCTAssertEqual(pixels.width, 3)
        XCTAssertEqual(pixels.height, 2)
        XCTAssertEqual(try pixels.row(0), [1, 2, 3])
        XCTAssertEqual(try pixels.row(1), [4, 5, 6])
        XCTAssertThrowsError(try pixels.row(-1))
        XCTAssertThrowsError(try pixels.row(2))
    }

    func test16BitByteOrdersAndTIFFRoundTrip() throws {
        for (bytes, order) in [
            ([UInt8(0), 0, 1, 0, 255, 255], CGBitmapInfo.byteOrder16Big),
            ([UInt8(0), 0, 0, 1, 255, 255], CGBitmapInfo.byteOrder16Little)
        ] {
            let source = try image(bytes, height: 1, bits: 16, order: order)
            XCTAssertEqual(try PixelImage(image: source).row(0), [0, 256, 65535])
            let url = temporaryURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try writeTIFF(source, to: url)
            let decoded = try PixelImage(contentsOf: url)
            XCTAssertEqual(decoded.bitDepth, 16)
            XCTAssertEqual(try decoded.row(0), [0, 256, 65535])
        }
    }

    func testRGBLuminance() throws {
        let source = try image([255, 0, 0, 0, 255, 0, 0, 0, 255], height: 1, color: true)
        let pixels = try PixelImage(image: source)
        XCTAssertTrue(pixels.isColor)
        let row = try pixels.row(0)
        XCTAssertEqual(row[0], 54.213, accuracy: 0.000001)
        XCTAssertEqual(row[1], 182.376, accuracy: 0.000001)
        XCTAssertEqual(row[2], 18.411, accuracy: 0.000001)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTIFF(source, to: url)
        XCTAssertEqual(try PixelImage(contentsOf: url).row(0), row)
    }

    func test16BitRGB() throws {
        let source = try image(
            [255, 255, 0, 0, 0, 0], width: 1, height: 1, bits: 16,
            color: true, order: .byteOrder16Big
        )
        let pixels = try PixelImage(image: source)
        XCTAssertEqual(try pixels.row(0)[0], 65535 * 0.2126, accuracy: 0.000001)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTIFF(source, to: url)
        XCTAssertEqual(try PixelImage(contentsOf: url).row(0), try pixels.row(0))
    }

    func testPaddedRGBByteLayouts() throws {
        for (bytes, alpha, order) in [
            ([UInt8(255), 0, 0, 42], CGImageAlphaInfo.noneSkipLast, CGBitmapInfo.byteOrder32Big),
            ([UInt8(42), 255, 0, 0], CGImageAlphaInfo.noneSkipFirst, CGBitmapInfo.byteOrder32Big),
            ([UInt8(42), 0, 0, 255], CGImageAlphaInfo.noneSkipLast, CGBitmapInfo.byteOrder32Little),
            ([UInt8(0), 0, 255, 42], CGImageAlphaInfo.noneSkipFirst, CGBitmapInfo.byteOrder32Little)
        ] {
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let source = try XCTUnwrap(CGImage(
                width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue).union(order),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            XCTAssertEqual(try PixelImage(image: source).row(0)[0], 54.213, accuracy: 0.000001)
        }
    }

    func testRejectsAlphaAndFloatingPoint() throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data([255, 0, 0, 255]) as CFData))
        let rgba = try XCTUnwrap(CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        XCTAssertThrowsError(try PixelImage(image: rgba))
        let floatImage = try XCTUnwrap(CGImage(
            width: 1, height: 1, bitsPerComponent: 32, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [.floatComponents, .byteOrder32Little],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        XCTAssertThrowsError(try PixelImage(image: floatImage))
    }

    func testOrientationFromTIFFMetadata() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try image([1, 2, 3, 4, 5, 6]),
                                  [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let pixels = try PixelImage(contentsOf: url)
        XCTAssertEqual(pixels.width, 2)
        XCTAssertEqual(pixels.height, 3)
        XCTAssertEqual(pixels.values, [4, 1, 5, 2, 6, 3])
    }

    func testAllOrientations() throws {
        let source = try image([1, 2, 3, 4, 5, 6])
        let expected: [[Double]] = [
            [1, 2, 3, 4, 5, 6], [3, 2, 1, 6, 5, 4],
            [6, 5, 4, 3, 2, 1], [4, 5, 6, 1, 2, 3],
            [1, 4, 2, 5, 3, 6], [4, 1, 5, 2, 6, 3],
            [6, 3, 5, 2, 4, 1], [3, 6, 2, 5, 1, 4]
        ]
        for orientation in 1...8 {
            let pixels = try PixelImage(image: source, orientation: orientation)
            XCTAssertEqual(pixels.values, expected[orientation - 1])
            XCTAssertEqual(pixels.width, orientation >= 5 ? 2 : 3)
            XCTAssertEqual(pixels.height, orientation >= 5 ? 3 : 2)
        }
        XCTAssertThrowsError(try PixelImage(image: source, orientation: 9))
    }

    func testPreviewDoesNotChangeSamples() throws {
        let pixels = try PixelImage(image: image([10, 20, 30, 40, 50, 60]))
        let preview = try pixels.preview()
        let bytes = try XCTUnwrap(preview.dataProvider?.data) as Data
        XCTAssertEqual(Array(bytes), [0, 51, 102, 153, 204, 255])
        XCTAssertEqual(try pixels.row(0), [10, 20, 30])
        let constant = try PixelImage(image: image([7], width: 1, height: 1))
        XCTAssertNoThrow(try constant.preview())
        XCTAssertEqual(try constant.row(0), [7])
    }

    func testExactExportShapeAndValues() throws {
        let url = temporaryURL(extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let pixels = try PixelImage(image: image([1, 2, 3, 4, 5, 6]))
        try pixels.save(row: 1, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "0\t4\n1\t5\n2\t6\n")
        try pixels.save(row: 0, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "0\t1\n1\t2\n2\t3\n")
        let rgb = try PixelImage(image: image([255, 0, 0], width: 1, height: 1, color: true))
        try rgb.save(row: 0, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "0\t54.213\n")
        XCTAssertThrowsError(try pixels.save(row: 2, to: url))
        XCTAssertThrowsError(try pixels.save(row: 0, to: url.appendingPathComponent("missing.txt")))
    }

    func testInvalidAndMultiPageFiles() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a TIFF".utf8).write(to: url)
        XCTAssertThrowsError(try PixelImage(contentsOf: url))
        try writeTIFF(image([1, 2, 3, 4, 5, 6]), to: url, pages: 2)
        XCTAssertThrowsError(try PixelImage(contentsOf: url)) { error in
            guard case ImageError.multiplePages = error else {
                return XCTFail("Expected multiple-page error, got \(error)")
            }
        }
    }

    func testProvidedStreakCameraSample() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/examples/12OKTR2.TIF")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("The local example TIFF is not included in version control.")
        }
        let pixels = try PixelImage(contentsOf: url)
        XCTAssertEqual(pixels.width, 512)
        XCTAssertEqual(pixels.height, 480)
        XCTAssertEqual(pixels.bitDepth, 8)
        XCTAssertEqual(Array(try pixels.row(0).prefix(8)), [6, 10, 10, 8, 7, 7, 5, 5])
        let output = temporaryURL(extension: "txt")
        defer { try? FileManager.default.removeItem(at: output) }
        try pixels.save(row: 240, to: output)
        let lines = try String(contentsOf: output, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 512)
        let expected = try pixels.row(240)
        for (index, line) in lines.enumerated() {
            let columns = line.split(separator: "\t")
            XCTAssertEqual(columns.count, 2)
            XCTAssertEqual(Int(columns[0]), index)
            XCTAssertEqual(Double(columns[1]), expected[index])
        }
    }
}
