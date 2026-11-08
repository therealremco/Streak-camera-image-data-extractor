import Foundation

/// Reader for the raw `.img` files written by the PC-TA acquisition software
/// (converted to TIFF by `TATOTIFF.EXE`, "PC-TA Image file conversion to TIFF
/// format", version 2.1, 1991).
///
/// The layout was worked out from the 1998 measurement files; there is no
/// published specification:
///
/// - A 256-byte header, little-endian:
///   - 0x96: day (UInt8), 0x97: month (UInt8), 0x98: year (UInt16),
///     0x9A–0x9D: hour, minute, second, hundredths (UInt8 each). All zero in
///     some files.
///   - 0xA8: last column index (UInt16), 0xAA: last row index (UInt16), so the
///     image is (x + 1) × (y + 1) pixels, 512 × 480 in every known file.
/// - Pixels as signed 16-bit little-endian integers, row by row from the top.
///   The data are 12-bit (maximum 4095) and background-subtracted, so small
///   negative values occur. Storage is padded to whole rows beyond the image
///   (512 rows for 480 used); the padding rows are ignored.
///
/// `TATOTIFF` writes `max(0, ⌊value · 255 / 4096⌋)` as 8-bit TIFF pixels (exact
/// for the 1998 sample), which loses 4 bits of resolution and clips the
/// negative background values to 0.
enum PCTAImage {
    static let headerSize = 256
    static let bitDepth = 12

    static func read(_ data: Data) throws -> PixelImage {
        guard data.count > headerSize else {
            throw ImageError.invalidPCTA("The file is shorter than the 256-byte PC-TA header.")
        }
        let bytes = [UInt8](data)
        func uint16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }

        let width = uint16(0xA8) + 1
        let height = uint16(0xAA) + 1
        let rowBytes = width * 2
        let pixelBytes = bytes.count - headerSize
        // A blank header would describe a 1 × 1 image; real files are 512 × 480.
        guard width * height > 1, pixelBytes % rowBytes == 0,
              pixelBytes / rowBytes >= height else {
            throw ImageError.invalidPCTA(
                "The header describes a \(width) × \(height) image, which does not match "
                + "the \(pixelBytes) bytes of pixel data.")
        }

        var values = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let offset = headerSize + 2 * index
            values[index] = Double(Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8))
        }

        var recorded: DateComponents?
        let year = uint16(0x98)
        if year > 0 {
            recorded = DateComponents(
                year: year, month: Int(bytes[0x97]), day: Int(bytes[0x96]),
                hour: Int(bytes[0x9A]), minute: Int(bytes[0x9B]), second: Int(bytes[0x9C]),
                nanosecond: Int(bytes[0x9D]) * 10_000_000)
        }
        return PixelImage(width: width, height: height, values: values, bitDepth: bitDepth,
                          isColor: false, formatName: "PC-TA image", headerTimestamp: recorded)
    }
}
