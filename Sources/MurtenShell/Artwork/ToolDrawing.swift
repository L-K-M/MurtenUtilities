import SwiftUI

/// Flat colour and tapered filled paths, with open space between limbs.
/// Shared poses keep head proportions and stroke character consistent.
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

    func leaningFigure(limbs: Color, shirt: Color, reaches hand: CGPoint) {
        ellipse(limbs, x: 39, y: 8, width: 19, height: 19)
        fill(shirt) { p in
            p.move(to: CGPoint(x: 49, y: 32))
            p.addCurve(to: CGPoint(x: 18, y: 66), control1: CGPoint(x: 34, y: 36), control2: CGPoint(x: 22, y: 49))
            p.addQuadCurve(to: CGPoint(x: 40, y: 59), control: CGPoint(x: 30, y: 66))
            p.addQuadCurve(to: CGPoint(x: 49, y: 32), control: CGPoint(x: 46, y: 45))
            p.closeSubpath()
        }
        fill(limbs) { p in
            p.move(to: CGPoint(x: 36, y: 36))
            p.addCurve(to: CGPoint(x: 18, y: 57), control1: CGPoint(x: 4, y: 29), control2: CGPoint(x: 7, y: 48))
            p.addCurve(to: CGPoint(x: 36, y: 36), control1: CGPoint(x: 5, y: 36), control2: CGPoint(x: 23, y: 37))
            p.closeSubpath()
            p.move(to: CGPoint(x: 46, y: 42))
            p.addCurve(to: hand, control1: CGPoint(x: 43, y: 65), control2: CGPoint(x: 56, y: 71))
            p.addQuadCurve(to: CGPoint(x: hand.x - 4, y: hand.y + 2),
                          control: CGPoint(x: hand.x + 2, y: hand.y + 5))
            p.addCurve(to: CGPoint(x: 46, y: 42), control1: CGPoint(x: 44, y: 74), control2: CGPoint(x: 40, y: 57))
            p.closeSubpath()
            p.move(to: CGPoint(x: 26, y: 71))
            p.addCurve(to: CGPoint(x: 29, y: 92), control1: CGPoint(x: 43, y: 78), control2: CGPoint(x: 37, y: 84))
            p.addCurve(to: CGPoint(x: 7, y: 114), control1: CGPoint(x: 20, y: 101), control2: CGPoint(x: 15, y: 107))
            p.addCurve(to: CGPoint(x: 29, y: 83), control1: CGPoint(x: 14, y: 103), control2: CGPoint(x: 22, y: 91))
            p.addCurve(to: CGPoint(x: 26, y: 71), control1: CGPoint(x: 36, y: 79), control2: CGPoint(x: 32, y: 76))
            p.closeSubpath()
            p.move(to: CGPoint(x: 41, y: 70))
            p.addCurve(to: CGPoint(x: 47, y: 104), control1: CGPoint(x: 38, y: 77), control2: CGPoint(x: 38, y: 92))
            p.addQuadCurve(to: CGPoint(x: 59, y: 112), control: CGPoint(x: 52, y: 110))
            p.addLine(to: CGPoint(x: 42, y: 112))
            p.addCurve(to: CGPoint(x: 33, y: 87), control1: CGPoint(x: 37, y: 104), control2: CGPoint(x: 34, y: 96))
            p.addQuadCurve(to: CGPoint(x: 41, y: 70), control: CGPoint(x: 32, y: 79))
            p.closeSubpath()
        }
    }

    func standingFigure(limbs: Color, shirt: Color) {
        ellipse(limbs, x: 26, y: 8, width: 19, height: 19)
        fill(shirt) { p in
            p.move(to: CGPoint(x: 40, y: 31))
            p.addCurve(to: CGPoint(x: 20, y: 67), control1: CGPoint(x: 28, y: 32), control2: CGPoint(x: 15, y: 47))
            p.addQuadCurve(to: CGPoint(x: 40, y: 61), control: CGPoint(x: 30, y: 69))
            p.addQuadCurve(to: CGPoint(x: 40, y: 31), control: CGPoint(x: 47, y: 44))
            p.closeSubpath()
        }
        fill(limbs) { p in
            p.move(to: CGPoint(x: 29, y: 34))
            p.addCurve(to: CGPoint(x: 17, y: 69), control1: CGPoint(x: 1, y: 42), control2: CGPoint(x: 8, y: 53))
            p.addQuadCurve(to: CGPoint(x: 11, y: 61), control: CGPoint(x: 5, y: 68))
            p.addCurve(to: CGPoint(x: 29, y: 34), control1: CGPoint(x: 23, y: 59), control2: CGPoint(x: 0, y: 47))
            p.closeSubpath()
            p.move(to: CGPoint(x: 43, y: 34))
            p.addCurve(to: CGPoint(x: 74, y: 38), control1: CGPoint(x: 54, y: 44), control2: CGPoint(x: 65, y: 24))
            p.addCurve(to: CGPoint(x: 43, y: 34), control1: CGPoint(x: 59, y: 34), control2: CGPoint(x: 54, y: 51))
            p.closeSubpath()
            p.move(to: CGPoint(x: 28, y: 72))
            p.addCurve(to: CGPoint(x: 24, y: 98), control1: CGPoint(x: 35, y: 79), control2: CGPoint(x: 29, y: 89))
            p.addQuadCurve(to: CGPoint(x: 25, y: 117), control: CGPoint(x: 17, y: 110))
            p.addQuadCurve(to: CGPoint(x: 19, y: 98), control: CGPoint(x: 11, y: 112))
            p.addCurve(to: CGPoint(x: 28, y: 72), control1: CGPoint(x: 25, y: 87), control2: CGPoint(x: 30, y: 83))
            p.closeSubpath()
            p.move(to: CGPoint(x: 40, y: 71))
            p.addCurve(to: CGPoint(x: 43, y: 101), control1: CGPoint(x: 36, y: 80), control2: CGPoint(x: 36, y: 92))
            p.addQuadCurve(to: CGPoint(x: 56, y: 114), control: CGPoint(x: 49, y: 109))
            p.addLine(to: CGPoint(x: 40, y: 113))
            p.addCurve(to: CGPoint(x: 31, y: 84), control1: CGPoint(x: 32, y: 104), control2: CGPoint(x: 30, y: 93))
            p.addQuadCurve(to: CGPoint(x: 40, y: 71), control: CGPoint(x: 34, y: 76))
            p.closeSubpath()
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
