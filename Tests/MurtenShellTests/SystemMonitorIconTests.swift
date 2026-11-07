import AppKit
import SwiftUI
import XCTest
import MurtenCore
@testable import MurtenShell

@MainActor
final class SystemMonitorIconTests: XCTestCase {
    func testMonitorViewportIsLandscape() throws {
        let bitmap = try render()

        // Teal is reserved for the display; the seated operator uses other inks.
        let viewport = try XCTUnwrap(
            tealBoundingBox(in: bitmap),
            "No teal display found in the rendered icon"
        )

        XCTAssertGreaterThan(viewport.width, 30, "Viewport must remain a substantial display")
        XCTAssertGreaterThan(viewport.height, 15, "Viewport must remain a substantial display")

        // Acceptance criterion: the monitor display is landscape, not portrait.
        // Independently established ratio bounds: width / height in [1.5, 1.8].
        let aspectRatio = viewport.width / viewport.height
        XCTAssertGreaterThanOrEqual(aspectRatio, 1.5,
            "Monitor viewport aspect ratio (\(aspectRatio)) is below 1.5; "
            + "the screen appears portrait or square rather than landscape")
        XCTAssertLessThanOrEqual(aspectRatio, 1.8,
            "Monitor viewport aspect ratio (\(aspectRatio)) exceeds 1.8; "
            + "the screen is excessively wide")
    }

    private func render() throws -> NSBitmapImageRep {
        let module = try XCTUnwrap(
            ModuleRegistry.all.first { $0.id == "coreography" },
            "ModuleRegistry must include the System Monitor (coreography)"
        )
        let renderer = ImageRenderer(
            content: ToolIcon(module: module).frame(width: 128, height: 128)
        )
        renderer.scale = 1
        let cgImage = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no CGImage")
        return NSBitmapImageRep(cgImage: cgImage)
    }

    /// Returns the bounding box of the teal opaque display pixels.
    /// Teal is defined as low red, moderate+ green and blue, with high alpha —
    /// matching the ToolDrawing.teal color (0, 0.55, 0.57).
    private func tealBoundingBox(in bitmap: NSBitmapImageRep) -> CGRect? {
        var bounds: CGRect?
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y),
                      isTeal(color) else { continue }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    private func isTeal(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB),
              rgb.alphaComponent > 0.75 else { return false }
        return rgb.redComponent < 0.15
            && rgb.greenComponent > 0.40
            && rgb.blueComponent > 0.40
    }
}
