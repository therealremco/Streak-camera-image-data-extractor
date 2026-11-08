import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageError: LocalizedError {
    case invalidTIFF
    case multiplePages
    case unsupportedPixels
    case invalidRow
    case invalidPCTA(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTIFF: return "The file could not be decoded as a TIFF image."
        case .multiplePages: return "This TIFF contains multiple pages. Please select a single-page TIFF."
        case .unsupportedPixels:
            return "Use an 8-bit or 16-bit unsigned grayscale or RGB TIFF, without an alpha channel."
        case .invalidRow: return "The selected row is outside the image."
        case .invalidPCTA(let reason): return "The file could not be read as a PC-TA image. \(reason)"
        }
    }
}

public struct PixelImage {
    public let width: Int
    public let height: Int
    public let values: [Double]
    public let bitDepth: Int
    public let isColor: Bool
    /// "TIFF" or "PC-TA image".
    public let formatName: String
    /// Date and time stored in a PC-TA header (the acquisition PC's clock);
    /// nil for TIFF files and for PC-TA files with a blank date.
    public let headerTimestamp: DateComponents?

    init(width: Int, height: Int, values: [Double], bitDepth: Int, isColor: Bool,
         formatName: String, headerTimestamp: DateComponents? = nil) {
        self.width = width
        self.height = height
        self.values = values
        self.bitDepth = bitDepth
        self.isColor = isColor
        self.formatName = formatName
        self.headerTimestamp = headerTimestamp
    }

    /// Opens a TIFF, or a raw PC-TA `.img` file (by extension, case-insensitive).
    public init(contentsOf url: URL) throws {
        if url.pathExtension.lowercased() == "img" {
            self = try PCTAImage.read(try Data(contentsOf: url))
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .tiff) == true else {
            throw ImageError.invalidTIFF
        }
        guard CGImageSourceGetCount(source) == 1 else { throw ImageError.multiplePages }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageError.invalidTIFF
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        try self.init(image: image, orientation: orientation)
    }

    public init(image: CGImage, orientation: Int = 1) throws {
        let bits = image.bitsPerComponent
        let color = image.colorSpace?.model == .rgb
        let channels = color ? 3 : 1
        let paddingFirst = image.alphaInfo == .noneSkipFirst
        let paddingLast = image.alphaInfo == .noneSkipLast
        let storageChannels = channels + ((paddingFirst || paddingLast) ? 1 : 0)
        guard (bits == 8 || bits == 16),
              (color || image.colorSpace?.model == .monochrome),
              !image.bitmapInfo.contains(.floatComponents),
              image.bitsPerPixel == bits * storageChannels,
              (image.alphaInfo == .none || (color && (paddingFirst || paddingLast))),
              (1...8).contains(orientation),
              let data = image.dataProvider?.data else {
            throw ImageError.unsupportedPixels
        }
        let bytes = data as Data
        let sampleBytes = bits / 8
        guard image.bytesPerRow >= image.width * storageChannels * sampleBytes,
              bytes.count >= image.bytesPerRow * image.height else {
            throw ImageError.invalidTIFF
        }
        let littleEndian = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder16Little
        let reversedBytes = bits == 8 && storageChannels == 4
            && image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little
        let rotated = orientation >= 5
        width = rotated ? image.height : image.width
        height = rotated ? image.width : image.height
        bitDepth = bits
        isColor = color
        formatName = "TIFF"
        headerTimestamp = nil
        var pixels = [Double](repeating: 0, count: width * height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * image.bytesPerRow + x * storageChannels * sampleBytes
                func component(_ channel: Int) -> Double {
                    let position = channel + (paddingFirst ? 1 : 0)
                    let index = offset + (reversedBytes ? storageChannels - 1 - position : position) * sampleBytes
                    if bits == 8 { return Double(bytes[index]) }
                    let first = UInt16(bytes[index])
                    let second = UInt16(bytes[index + 1])
                    return Double(littleEndian ? first | second << 8 : first << 8 | second)
                }
                let value = color
                    ? 0.2126 * component(0) + 0.7152 * component(1) + 0.0722 * component(2)
                    : component(0)
                let destination: (Int, Int)
                switch orientation {
                case 2: destination = (image.width - 1 - x, y)
                case 3: destination = (image.width - 1 - x, image.height - 1 - y)
                case 4: destination = (x, image.height - 1 - y)
                case 5: destination = (y, x)
                case 6: destination = (image.height - 1 - y, x)
                case 7: destination = (image.height - 1 - y, image.width - 1 - x)
                case 8: destination = (y, image.width - 1 - x)
                default: destination = (x, y)
                }
                pixels[destination.1 * width + destination.0] = value
            }
        }
        values = pixels
    }

    public func row(_ index: Int) throws -> [Double] {
        guard (0..<height).contains(index) else { throw ImageError.invalidRow }
        return Array(values[(index * width)..<((index + 1) * width)])
    }

    public func save(row index: Int, to url: URL) throws {
        let samples = try row(index)
        let text = samples.enumerated().map { x, y in
            "\(x)\t\(y.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...10))))"
        }.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func preview() throws -> CGImage {
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let range = maximum - minimum
        let pixels = values.map { value -> UInt8 in
            range > 0 ? UInt8(max(0, min(255, ((value - minimum) / range * 255).rounded()))) : 0
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw ImageError.invalidTIFF }
        return image
    }
}
