import AppKit
import SwiftUI
import XCTest
import MurtenCore
@testable import MurtenShell

@MainActor
final class ToolIconTests: XCTestCase {
    func testCleanupTorsoIsNotCompressedUnderItsHead() throws {
        let bitmap = try render(width: 128, height: 128)
        let head = try XCTUnwrap(bounds(in: bitmap, ink: .teal, firstBandOnly: true))
        let torso = try XCTUnwrap(bounds(in: bitmap, ink: .blue))
        XCTAssertGreaterThanOrEqual(torso.height, head.height * 1.5,
                                    "The flowing torso needs room beneath the head, rather than a compact wedge")
    }

    func testHeadsStayRoundInSquareWideAndTallFrames() throws {
        for size in [CGSize(width: 72, height: 72), CGSize(width: 128, height: 128),
                     CGSize(width: 160, height: 80), CGSize(width: 80, height: 160)] {
            let bitmap = try render(width: size.width, height: size.height)
            let head = try XCTUnwrap(bounds(in: bitmap, ink: .teal, firstBandOnly: true))
            XCTAssertEqual(head.width, head.height, accuracy: 1, "Round head in \(size)")
            XCTAssertGreaterThan(head.minX, 0)
            XCTAssertGreaterThan(head.minY, 0)
            XCTAssertLessThan(head.maxX, CGFloat(bitmap.pixelsWide))
            XCTAssertLessThan(head.maxY, CGFloat(bitmap.pixelsHigh))
        }
    }

    private enum Ink {
        case teal, blue

        func matches(_ color: NSColor) -> Bool {
            guard let rgb = color.usingColorSpace(.sRGB), rgb.alphaComponent > 0.75 else { return false }
            switch self {
            case .teal:
                return rgb.redComponent < 0.1 && rgb.greenComponent > 0.4 && rgb.blueComponent > 0.4
            case .blue:
                return rgb.redComponent < 0.4 && rgb.greenComponent < 0.5 && rgb.blueComponent > 0.65
            }
        }
    }

    private func render(width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
        let module = try XCTUnwrap(ModuleRegistry.all.first { $0.id == "repomen" })
        let renderer = ImageRenderer(content: ToolIcon(module: module).frame(width: width, height: height))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func bounds(in bitmap: NSBitmapImageRep, ink: Ink, firstBandOnly: Bool = false) -> CGRect? {
        var result: CGRect?
        for y in 0..<bitmap.pixelsHigh {
            var foundInRow = false
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), ink.matches(color) else { continue }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                result = result.map { $0.union(pixel) } ?? pixel
                foundInRow = true
            }
            if firstBandOnly, result != nil, !foundInRow { break }
        }
        return result
    }
}
