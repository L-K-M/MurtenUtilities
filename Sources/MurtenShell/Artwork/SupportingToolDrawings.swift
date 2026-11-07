import SwiftUI

extension ToolDrawing {
    func startupManager() {
        // The braced legs have clear knees; the raised foot rests on the housing.
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 71, y: 120))
            p.addCurve(to: CGPoint(x: 96, y: 94), control1: CGPoint(x: 71, y: 106), control2: CGPoint(x: 82, y: 94))
            p.addCurve(to: CGPoint(x: 121, y: 120), control1: CGPoint(x: 110, y: 94), control2: CGPoint(x: 121, y: 106))
            p.closeSubpath()
        }
        stroke(Self.teal, width: 7) { p in
            p.move(to: CGPoint(x: 69, y: 26))
            p.addLine(to: CGPoint(x: 99, y: 101))
        }
        ellipse(Self.coral, x: 59, y: 15, width: 19, height: 19)
        stroke(Self.coral, width: 8.5) { p in
            p.move(to: CGPoint(x: 43, y: 77))
            p.addLine(to: CGPoint(x: 28, y: 98))
            p.addLine(to: CGPoint(x: 15, y: 116))
            p.addLine(to: CGPoint(x: 27, y: 116))
            p.move(to: CGPoint(x: 43, y: 77))
            p.addLine(to: CGPoint(x: 70, y: 74))
            p.addLine(to: CGPoint(x: 77, y: 101))
            p.addLine(to: CGPoint(x: 88, y: 102))
        }
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 33, y: 35))
            p.addCurve(to: CGPoint(x: 44, y: 74), control1: CGPoint(x: 24, y: 41), control2: CGPoint(x: 51, y: 54))
            p.addQuadCurve(to: CGPoint(x: 34, y: 84), control: CGPoint(x: 42, y: 81))
            p.addCurve(to: CGPoint(x: 36, y: 61), control1: CGPoint(x: 39, y: 75), control2: CGPoint(x: 40, y: 69))
            p.addCurve(to: CGPoint(x: 33, y: 35), control1: CGPoint(x: 30, y: 52), control2: CGPoint(x: 21, y: 40))
            p.closeSubpath()
            p.move(to: CGPoint(x: 32, y: 34))
            p.addCurve(to: CGPoint(x: 65, y: 25), control1: CGPoint(x: 46, y: 33), control2: CGPoint(x: 55, y: 28))
            p.addLine(to: CGPoint(x: 68, y: 30))
            p.addCurve(to: CGPoint(x: 32, y: 34), control1: CGPoint(x: 54, y: 36), control2: CGPoint(x: 40, y: 39))
            p.closeSubpath()
            p.move(to: CGPoint(x: 33, y: 40))
            p.addCurve(to: CGPoint(x: 70, y: 29), control1: CGPoint(x: 45, y: 48), control2: CGPoint(x: 64, y: 38))
            p.addQuadCurve(to: CGPoint(x: 73, y: 34), control: CGPoint(x: 74, y: 27))
            p.addCurve(to: CGPoint(x: 37, y: 49), control1: CGPoint(x: 60, y: 48), control2: CGPoint(x: 46, y: 53))
            p.addQuadCurve(to: CGPoint(x: 33, y: 40), control: CGPoint(x: 30, y: 47))
            p.closeSubpath()
        }
        ellipse(Self.teal, x: 14, y: 12, width: 20, height: 20)
        stroke(.white, width: 3.5) { p in
            p.addArc(center: CGPoint(x: 97, y: 108), radius: 8,
                     startAngle: .degrees(-45), endAngle: .degrees(225), clockwise: false)
            p.move(to: CGPoint(x: 97, y: 98))
            p.addLine(to: CGPoint(x: 97, y: 107))
        }
    }

    func sessionRecovery() {
        // A restored window is cradled in a seated figure's lap.
        stroke(Self.blue, width: 6) { p in
            p.move(to: CGPoint(x: 108, y: 57))
            p.addCurve(to: CGPoint(x: 61, y: 12), control1: CGPoint(x: 116, y: 26), control2: CGPoint(x: 86, y: 10))
            p.addCurve(to: CGPoint(x: 18, y: 45), control1: CGPoint(x: 35, y: 11), control2: CGPoint(x: 13, y: 25))
        }
        polygon(Self.blue, CGPoint(x: 9, y: 41), CGPoint(x: 21, y: 57), CGPoint(x: 30, y: 39))
        ellipse(Self.teal, x: 54, y: 33, width: 19, height: 19)
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 62, y: 57))
            p.addCurve(to: CGPoint(x: 47, y: 86), control1: CGPoint(x: 53, y: 63), control2: CGPoint(x: 45, y: 77))
            p.addQuadCurve(to: CGPoint(x: 78, y: 87), control: CGPoint(x: 63, y: 95))
            p.addCurve(to: CGPoint(x: 69, y: 57), control1: CGPoint(x: 81, y: 73), control2: CGPoint(x: 72, y: 62))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 58, y: 97))
            p.addCurve(to: CGPoint(x: 20, y: 107), control1: CGPoint(x: 45, y: 90), control2: CGPoint(x: 28, y: 97))
            p.addCurve(to: CGPoint(x: 39, y: 114), control1: CGPoint(x: 12, y: 115), control2: CGPoint(x: 29, y: 118))
            p.addLine(to: CGPoint(x: 76, y: 105))
            p.addQuadCurve(to: CGPoint(x: 58, y: 97), control: CGPoint(x: 70, y: 100))
            p.closeSubpath()
            p.move(to: CGPoint(x: 72, y: 97))
            p.addCurve(to: CGPoint(x: 110, y: 108), control1: CGPoint(x: 86, y: 90), control2: CGPoint(x: 103, y: 99))
            p.addCurve(to: CGPoint(x: 88, y: 114), control1: CGPoint(x: 118, y: 116), control2: CGPoint(x: 100, y: 118))
            p.addLine(to: CGPoint(x: 51, y: 105))
            p.addQuadCurve(to: CGPoint(x: 72, y: 97), control: CGPoint(x: 59, y: 99))
            p.closeSubpath()
        }
        box(Self.teal, x: 42, y: 76, width: 45, height: 28, radius: 4)
        box(.white, x: 46, y: 80, width: 37, height: 20, radius: 2)
        box(Self.yellow, x: 46, y: 80, width: 37, height: 6, radius: 1)
        box(Self.blue, x: 51, y: 90, width: 12, height: 6, radius: 1)
        box(Self.teal, x: 67, y: 90, width: 11, height: 6, radius: 1)
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 58, y: 64))
            p.addCurve(to: CGPoint(x: 44, y: 88), control1: CGPoint(x: 40, y: 65), control2: CGPoint(x: 36, y: 80))
            p.addQuadCurve(to: CGPoint(x: 49, y: 84), control: CGPoint(x: 51, y: 93))
            p.addCurve(to: CGPoint(x: 58, y: 64), control1: CGPoint(x: 41, y: 81), control2: CGPoint(x: 45, y: 69))
            p.closeSubpath()
            p.move(to: CGPoint(x: 71, y: 64))
            p.addCurve(to: CGPoint(x: 87, y: 88), control1: CGPoint(x: 88, y: 65), control2: CGPoint(x: 94, y: 80))
            p.addQuadCurve(to: CGPoint(x: 81, y: 84), control: CGPoint(x: 81, y: 93))
            p.addCurve(to: CGPoint(x: 71, y: 64), control1: CGPoint(x: 89, y: 81), control2: CGPoint(x: 83, y: 68))
            p.closeSubpath()
        }
    }

    func softwareUpdates() {
        // Both shoes stand on the middle rung; the free hand holds the rail.
        stroke(Self.blue, width: 3.5) { p in
            p.move(to: CGPoint(x: 86, y: 67)); p.addLine(to: CGPoint(x: 76, y: 120))
            p.move(to: CGPoint(x: 110, y: 67)); p.addLine(to: CGPoint(x: 120, y: 120))
            p.move(to: CGPoint(x: 84, y: 80)); p.addLine(to: CGPoint(x: 112, y: 80))
            p.move(to: CGPoint(x: 80, y: 100)); p.addLine(to: CGPoint(x: 116, y: 100))
            p.move(to: CGPoint(x: 77, y: 116)); p.addLine(to: CGPoint(x: 119, y: 116))
        }
        stroke(Self.blue, width: 5) { p in
            p.move(to: CGPoint(x: 13, y: 96)); p.addLine(to: CGPoint(x: 17, y: 113))
            p.addLine(to: CGPoint(x: 64, y: 113)); p.addLine(to: CGPoint(x: 68, y: 96))
        }
        stroke(Self.coral, width: 6.5) { p in
            p.move(to: CGPoint(x: 97, y: 69))
            p.addLine(to: CGPoint(x: 91, y: 83))
            p.addLine(to: CGPoint(x: 91, y: 97))
            p.addLine(to: CGPoint(x: 99, y: 97))
            p.move(to: CGPoint(x: 101, y: 69))
            p.addLine(to: CGPoint(x: 109, y: 83))
            p.addLine(to: CGPoint(x: 107, y: 97))
            p.addLine(to: CGPoint(x: 114, y: 97))
        }
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 90, y: 39))
            p.addCurve(to: CGPoint(x: 95, y: 75), control1: CGPoint(x: 79, y: 43), control2: CGPoint(x: 79, y: 56))
            p.addQuadCurve(to: CGPoint(x: 104, y: 69), control: CGPoint(x: 101, y: 76))
            p.addCurve(to: CGPoint(x: 90, y: 39), control1: CGPoint(x: 103, y: 56), control2: CGPoint(x: 100, y: 47))
            p.closeSubpath()
        }
        ellipse(Self.coral, x: 85, y: 15, width: 19, height: 19)
        box(Self.yellow, x: 22, y: 49, width: 36, height: 34, radius: 4)
        polygon(.white, CGPoint(x: 36, y: 55), CGPoint(x: 44, y: 55),
                CGPoint(x: 44, y: 67), CGPoint(x: 50, y: 67), CGPoint(x: 40, y: 77),
                CGPoint(x: 30, y: 67), CGPoint(x: 36, y: 67))
        stroke(Self.coral, width: 5) { p in
            p.move(to: CGPoint(x: 88, y: 46))
            p.addLine(to: CGPoint(x: 74, y: 54))
            p.addLine(to: CGPoint(x: 57, y: 61))
            p.move(to: CGPoint(x: 99, y: 46))
            p.addLine(to: CGPoint(x: 113, y: 57))
            p.addLine(to: CGPoint(x: 110, y: 69))
        }
    }
}
