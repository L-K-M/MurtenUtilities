import SwiftUI

extension ToolDrawing {
    func runnerManager() {
        ellipse(Self.blue, x: 43, y: 8, width: 19, height: 19)
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 52, y: 31))
            p.addQuadCurve(to: CGPoint(x: 27, y: 70), control: CGPoint(x: 34, y: 40))
            p.addQuadCurve(to: CGPoint(x: 46, y: 59), control: CGPoint(x: 43, y: 68))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 39, y: 37))
            p.addCurve(to: CGPoint(x: 15, y: 61), control1: CGPoint(x: 23, y: 25), control2: CGPoint(x: 13, y: 38))
            p.addQuadCurve(to: CGPoint(x: 30, y: 53), control: CGPoint(x: 31, y: 62))
            p.addQuadCurve(to: CGPoint(x: 20, y: 53), control: CGPoint(x: 24, y: 57))
            p.addQuadCurve(to: CGPoint(x: 39, y: 37), control: CGPoint(x: 18, y: 36))
            p.closeSubpath()
            p.move(to: CGPoint(x: 49, y: 40))
            p.addCurve(to: CGPoint(x: 73, y: 44), control1: CGPoint(x: 49, y: 63), control2: CGPoint(x: 65, y: 61))
            p.addQuadCurve(to: CGPoint(x: 67, y: 36), control: CGPoint(x: 77, y: 29))
            p.addCurve(to: CGPoint(x: 49, y: 40), control1: CGPoint(x: 70, y: 60), control2: CGPoint(x: 54, y: 62))
            p.closeSubpath()
            p.move(to: CGPoint(x: 32, y: 68))
            p.addCurve(to: CGPoint(x: 8, y: 109), control1: CGPoint(x: 12, y: 78), control2: CGPoint(x: 24, y: 91))
            p.addCurve(to: CGPoint(x: 32, y: 68), control1: CGPoint(x: 36, y: 90), control2: CGPoint(x: 17, y: 85))
            p.closeSubpath()
            p.move(to: CGPoint(x: 43, y: 65))
            p.addCurve(to: CGPoint(x: 78, y: 101), control1: CGPoint(x: 39, y: 89), control2: CGPoint(x: 64, y: 83))
            p.addQuadCurve(to: CGPoint(x: 56, y: 91), control: CGPoint(x: 72, y: 88))
            p.addQuadCurve(to: CGPoint(x: 43, y: 65), control: CGPoint(x: 30, y: 90))
            p.closeSubpath()
        }
        stroke(Self.teal, width: 4) { p in
            p.move(to: CGPoint(x: 93, y: 37)); p.addLine(to: CGPoint(x: 105, y: 65))
            p.addLine(to: CGPoint(x: 93, y: 93))
        }
        box(Self.yellow, x: 82, y: 23, width: 23, height: 23, radius: 5)
        box(Self.teal, x: 95, y: 54, width: 23, height: 23, radius: 5)
        box(Self.lime, x: 82, y: 85, width: 23, height: 23, radius: 5)
        stroke(.white, width: 3) { p in
            p.move(to: CGPoint(x: 88, y: 96)); p.addLine(to: CGPoint(x: 93, y: 100))
            p.addLine(to: CGPoint(x: 100, y: 91))
        }
    }

    func systemMonitor() {
        standingFigure(limbs: Self.coral, shirt: Self.teal)
        polygon(Self.yellow, CGPoint(x: 114, y: 48), CGPoint(x: 123, y: 54),
                CGPoint(x: 123, y: 86), CGPoint(x: 114, y: 92))
        box(Self.blue, x: 52, y: 45, width: 64, height: 48, radius: 7)
        box(.white, x: 57, y: 50, width: 54, height: 36, radius: 4)
        box(Self.teal, x: 61, y: 54, width: 46, height: 28, radius: 2)
        polygon(Self.yellow, CGPoint(x: 77, y: 92), CGPoint(x: 91, y: 92),
                CGPoint(x: 95, y: 105), CGPoint(x: 106, y: 112),
                CGPoint(x: 63, y: 112), CGPoint(x: 75, y: 105))
        stroke(.white, width: 2.5) { p in
            p.move(to: CGPoint(x: 65, y: 68)); p.addLine(to: CGPoint(x: 73, y: 68))
            p.addLine(to: CGPoint(x: 79, y: 58)); p.addLine(to: CGPoint(x: 87, y: 77))
            p.addLine(to: CGPoint(x: 94, y: 66)); p.addLine(to: CGPoint(x: 103, y: 66))
            p.move(to: CGPoint(x: 117, y: 62)); p.addLine(to: CGPoint(x: 120, y: 60))
            p.move(to: CGPoint(x: 117, y: 72)); p.addLine(to: CGPoint(x: 120, y: 70))
        }
    }
}
