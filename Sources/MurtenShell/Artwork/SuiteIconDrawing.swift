import SwiftUI

extension ToolDrawing {
    /// A general-purpose toolkit, distinct from any one module's task.
    func suiteIcon() {
        leaningFigure(limbs: Self.teal, shirt: Self.coral, reaches: CGPoint(x: 78, y: 63))

        // Tool handles emerge behind the case and remain clear at Dock size.
        stroke(Self.blue, width: 8) { p in
            p.move(to: CGPoint(x: 105, y: 79))
            p.addLine(to: CGPoint(x: 112, y: 49))
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 109, y: 48))
            p.addCurve(to: CGPoint(x: 105, y: 28), control1: CGPoint(x: 98, y: 43), control2: CGPoint(x: 101, y: 34))
            p.addLine(to: CGPoint(x: 108, y: 38))
            p.addLine(to: CGPoint(x: 115, y: 40))
            p.addLine(to: CGPoint(x: 121, y: 32))
            p.addCurve(to: CGPoint(x: 116, y: 50), control1: CGPoint(x: 126, y: 42), control2: CGPoint(x: 122, y: 48))
            p.closeSubpath()
        }
        stroke(Self.yellow, width: 4) { p in
            p.move(to: CGPoint(x: 81, y: 48)); p.addLine(to: CGPoint(x: 89, y: 82))
        }
        box(Self.lime, x: 76, y: 36, width: 10, height: 23, radius: 4)

        stroke(Self.blue, width: 5) { p in
            p.move(to: CGPoint(x: 80, y: 77)); p.addLine(to: CGPoint(x: 80, y: 67))
            p.addQuadCurve(to: CGPoint(x: 88, y: 59), control: CGPoint(x: 80, y: 59))
            p.addLine(to: CGPoint(x: 100, y: 59))
            p.addQuadCurve(to: CGPoint(x: 108, y: 67), control: CGPoint(x: 108, y: 59))
            p.addLine(to: CGPoint(x: 108, y: 77))
        }
        box(Self.blue, x: 61, y: 75, width: 62, height: 37, radius: 6)
        box(Self.yellow, x: 65, y: 83, width: 54, height: 25, radius: 3)
        box(Self.coral, x: 74, y: 77, width: 7, height: 14, radius: 2)
        box(Self.coral, x: 105, y: 77, width: 7, height: 14, radius: 2)
    }
}
