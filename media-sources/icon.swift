import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Compiled with the production ToolDrawing and SuiteIconDrawing sources by
// scripts/generate-app-icon.sh, so the Dock icon shares the suite's artwork.
@main
struct AppIconGenerator {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: generate-app-icon OUTPUT_PNG\n".utf8))
            exit(1)
        }
        let icon = Canvas { context, size in
            let side = min(size.width, size.height)
            let plate = CGRect(x: side / 16, y: side / 16,
                               width: side * 7 / 8, height: side * 7 / 8)
            context.fill(Path(roundedRect: plate, cornerRadius: side * 0.185),
                         with: .color(Color(red: 0.985, green: 0.982, blue: 0.965)))
            context.translateBy(x: side * 0.10, y: side * 0.10)
            let scale = side * 0.80 / ToolDrawing.canvasSide
            context.scaleBy(x: scale, y: scale)
            ToolDrawing(context: context).suiteIcon()
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        print("Wrote \(CommandLine.arguments[1]) (1024×1024, RGBA)")
    }
}
