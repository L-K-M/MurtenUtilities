import CoreFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Resample a square raster source (≥ 1024×1024) into all ten standard macOS
// iconset PNGs at 16, 32, 128, 256, 512 points × 1x/2x.

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("Usage: make-icon.swift SOURCE_PNG OUTPUT_ICONSET\n".data(using: .utf8)!)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: args[1])
let destination = URL(fileURLWithPath: args[2], isDirectory: true)

// Load source image via CGImage
guard let sourceData = try? Data(contentsOf: sourceURL),
      let sourceProvider = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(sourceProvider, 0, nil) else {
    FileHandle.standardError.write("Error: cannot load image from \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let srcWidth = sourceImage.width
let srcHeight = sourceImage.height

guard srcWidth == srcHeight else {
    FileHandle.standardError.write("Error: source image must be square (\(srcWidth)×\(srcHeight))\n".data(using: .utf8)!)
    exit(1)
}

guard srcWidth >= 1024 else {
    FileHandle.standardError.write("Error: source image must be at least 1024×1024 (\(srcWidth)×\(srcHeight))\n".data(using: .utf8)!)
    exit(1)
}

// Create the iconset directory
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

let sizes: [Int] = [16, 32, 128, 256, 512]
let scales: [Int] = [1, 2]

for size in sizes {
    for scale in scales {
        let pixels = size * scale

        // Create a bitmap context at the exact target pixel dimensions
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            FileHandle.standardError.write("Error: cannot create graphics context for \(pixels)×\(pixels)\n".data(using: .utf8)!)
            exit(1)
        }

        // Draw with high-quality resampling
        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))

        guard let resizedImage = context.makeImage() else {
            FileHandle.standardError.write("Error: cannot render image for \(pixels)×\(pixels)\n".data(using: .utf8)!)
            exit(1)
        }

        // Write PNG using ImageIO
        let suffix = scale == 2 ? "@2x" : ""
        let fileName = "icon_\(size)x\(size)\(suffix).png"
        let outputURL = destination.appendingPathComponent(fileName)

        guard let destProvider = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            FileHandle.standardError.write("Error: cannot create image destination for \(fileName)\n".data(using: .utf8)!)
            exit(1)
        }

        CGImageDestinationAddImage(destProvider, resizedImage, nil)
        guard CGImageDestinationFinalize(destProvider) else {
            FileHandle.standardError.write("Error: cannot write \(fileName)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
