import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root: swift scripts/test-iconset.swift
private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func context(size: Int) throws -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.byteOrder32Big.rawValue) else {
        throw VerificationFailure("Cannot create an RGBA context")
    }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    return context
}

private func verify() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("iconset-\(UUID())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let fixture = try context(size: 1024)
    fixture.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    fixture.fill(CGRect(x: 256, y: 256, width: 512, height: 512))
    let fixtureURL = temporary.appendingPathComponent("fixture.png")
    guard let image = fixture.makeImage(),
          let destination = CGImageDestinationCreateWithURL(fixtureURL as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else {
        throw VerificationFailure("Cannot create the fixture PNG")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw VerificationFailure("Cannot write the fixture") }

    let output = temporary.appendingPathComponent("iconset")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swift", "scripts/make-icon.swift", fixtureURL.path, output.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw VerificationFailure("make-icon.swift failed: \(String(decoding: diagnostics, as: UTF8.self))")
    }

    var checked = 0
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            guard let source = CGImageSourceCreateWithURL(output.appendingPathComponent(name) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw VerificationFailure("Cannot read \(name)")
            }
            guard image.width == pixels, image.height == pixels else {
                throw VerificationFailure("\(name): expected \(pixels)×\(pixels), got \(image.width)×\(image.height)")
            }
            let decoded = try context(size: pixels)
            defer { withExtendedLifetime(decoded) {} }
            decoded.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            guard let rgba = decoded.data?.assumingMemoryBound(to: UInt8.self) else {
                throw VerificationFailure("\(name): cannot read decoded RGBA pixels")
            }
            for (x, y) in [(0, 0), (pixels - 1, 0), (0, pixels - 1), (pixels - 1, pixels - 1)] {
                let alpha = rgba[(y * pixels + x) * 4 + 3]
                guard alpha == 0 else {
                    throw VerificationFailure("\(name): corner alpha \(alpha), expected 0")
                }
            }
            let center = ((pixels / 2) * pixels + pixels / 2) * 4
            guard rgba[center] == 255, rgba[center + 1] == 0,
                  rgba[center + 2] == 0, rgba[center + 3] == 255 else {
                throw VerificationFailure("\(name): expected an opaque red center in decoded RGBA")
            }
            checked += 1
        }
    }
    print("Verified \(checked) iconset images: exact sizes, transparent corners and opaque red centers")
}

do {
    try verify()
} catch {
    FileHandle.standardError.write(Data("Iconset verification failed: \(error)\n".utf8))
    exit(1)
}
