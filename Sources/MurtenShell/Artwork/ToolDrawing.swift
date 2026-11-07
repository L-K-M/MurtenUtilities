import SwiftUI

/// Flat colour and tapered filled paths, with open space between limbs.
/// Shared inks and primitives keep distinct actions in one illustration family.
struct ToolDrawing {
    let context: GraphicsContext

    static let canvasSide: CGFloat = 128

    static let teal = Color(red: 0, green: 0.55, blue: 0.57)
    static let blue = Color(red: 0.20, green: 0.33, blue: 0.86)
    static let yellow = Color(red: 0.97, green: 0.78, blue: 0.18)
    static let coral = Color(red: 0.96, green: 0.36, blue: 0.34)
    static let lime = Color(red: 0.66, green: 0.80, blue: 0.24)

    func fill(_ color: Color, _ build: (inout Path) -> Void) {
        var path = Path()
        build(&path)
        context.fill(path, with: .color(color))
    }

    func stroke(_ color: Color, width: CGFloat, _ build: (inout Path) -> Void) {
        var path = Path()
        build(&path)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    func ellipse(_ color: Color, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)), with: .color(color))
    }

    func box(_ color: Color, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat = 0) {
        context.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: height),
                          cornerRadius: radius), with: .color(color))
    }

    func polygon(_ color: Color, _ points: CGPoint...) {
        fill(color) { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }


    func document(_ color: Color, x: CGFloat, y: CGFloat, size: CGFloat = 19) {
        stroke(color, width: 3.5) { p in
            p.move(to: CGPoint(x: x, y: y + size))
            p.addLine(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + size * 0.6, y: y))
            p.addLine(to: CGPoint(x: x + size, y: y + size * 0.4))
            p.addLine(to: CGPoint(x: x + size, y: y + size))
            p.closeSubpath()
            p.move(to: CGPoint(x: x + size * 0.6, y: y))
            p.addLine(to: CGPoint(x: x + size * 0.6, y: y + size * 0.4))
            p.addLine(to: CGPoint(x: x + size, y: y + size * 0.4))
        }
    }

    func magnifier(_ color: Color, x: CGFloat, y: CGFloat, radius: CGFloat = 13) {
        stroke(color, width: 5) { p in
            p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            p.move(to: CGPoint(x: x - radius * 0.7, y: y + radius * 0.7))
            p.addLine(to: CGPoint(x: x - radius * 1.65, y: y + radius * 1.65))
        }
    }
}
