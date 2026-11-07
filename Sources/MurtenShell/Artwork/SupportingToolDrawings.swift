import SwiftUI

extension ToolDrawing {
    func startupManager() {
        // The lever and the braced figure share one strong diagonal.
        stroke(Self.teal, width: 7) { p in
            p.move(to: CGPoint(x: 69, y: 26))
            p.addLine(to: CGPoint(x: 99, y: 101))
        }
        ellipse(Self.coral, x: 59, y: 15, width: 19, height: 19)
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
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 43, y: 73))
            p.addCurve(to: CGPoint(x: 79, y: 66), control1: CGPoint(x: 58, y: 65), control2: CGPoint(x: 72, y: 64))
            p.addQuadCurve(to: CGPoint(x: 85, y: 75), control: CGPoint(x: 85, y: 65))
            p.addLine(to: CGPoint(x: 86, y: 99))
            p.addQuadCurve(to: CGPoint(x: 99, y: 98), control: CGPoint(x: 94, y: 93))
            p.addQuadCurve(to: CGPoint(x: 88, y: 108), control: CGPoint(x: 105, y: 102))
            p.addLine(to: CGPoint(x: 77, y: 111))
            p.addLine(to: CGPoint(x: 74, y: 78))
            p.addCurve(to: CGPoint(x: 48, y: 85), control1: CGPoint(x: 65, y: 78), control2: CGPoint(x: 57, y: 82))
            p.closeSubpath()
            p.move(to: CGPoint(x: 44, y: 75))
            p.addCurve(to: CGPoint(x: 24, y: 106), control1: CGPoint(x: 36, y: 88), control2: CGPoint(x: 30, y: 97))
            p.addLine(to: CGPoint(x: 14, y: 115))
            p.addQuadCurve(to: CGPoint(x: 28, y: 119), control: CGPoint(x: 24, y: 114))
            p.addLine(to: CGPoint(x: 7, y: 119))
            p.addCurve(to: CGPoint(x: 34, y: 81), control1: CGPoint(x: 17, y: 105), control2: CGPoint(x: 27, y: 87))
            p.addQuadCurve(to: CGPoint(x: 44, y: 75), control: CGPoint(x: 39, y: 76))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 71, y: 120))
            p.addCurve(to: CGPoint(x: 96, y: 94), control1: CGPoint(x: 71, y: 106), control2: CGPoint(x: 82, y: 94))
            p.addCurve(to: CGPoint(x: 121, y: 120), control1: CGPoint(x: 110, y: 94), control2: CGPoint(x: 121, y: 106))
            p.closeSubpath()
        }
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
            p.move(to: CGPoint(x: 53, y: 61))
            p.addCurve(to: CGPoint(x: 44, y: 88), control1: CGPoint(x: 37, y: 64), control2: CGPoint(x: 36, y: 80))
            p.addQuadCurve(to: CGPoint(x: 49, y: 84), control: CGPoint(x: 51, y: 93))
            p.addCurve(to: CGPoint(x: 53, y: 61), control1: CGPoint(x: 41, y: 81), control2: CGPoint(x: 45, y: 69))
            p.closeSubpath()
            p.move(to: CGPoint(x: 75, y: 61))
            p.addCurve(to: CGPoint(x: 87, y: 88), control1: CGPoint(x: 90, y: 65), control2: CGPoint(x: 94, y: 80))
            p.addQuadCurve(to: CGPoint(x: 81, y: 84), control: CGPoint(x: 81, y: 93))
            p.addCurve(to: CGPoint(x: 75, y: 61), control1: CGPoint(x: 89, y: 81), control2: CGPoint(x: 83, y: 68))
            p.closeSubpath()
        }
    }

    func softwareUpdates() {
        // The elevated helper lowers a download into the tray below.
        stroke(Self.blue, width: 3.5) { p in
            p.move(to: CGPoint(x: 87, y: 67)); p.addLine(to: CGPoint(x: 79, y: 119))
            p.move(to: CGPoint(x: 108, y: 67)); p.addLine(to: CGPoint(x: 116, y: 119))
            p.move(to: CGPoint(x: 85, y: 80)); p.addLine(to: CGPoint(x: 110, y: 80))
            p.move(to: CGPoint(x: 83, y: 96)); p.addLine(to: CGPoint(x: 112, y: 96))
            p.move(to: CGPoint(x: 81, y: 112)); p.addLine(to: CGPoint(x: 114, y: 112))
        }
        stroke(Self.blue, width: 5) { p in
            p.move(to: CGPoint(x: 13, y: 96)); p.addLine(to: CGPoint(x: 17, y: 113))
            p.addLine(to: CGPoint(x: 64, y: 113)); p.addLine(to: CGPoint(x: 68, y: 96))
        }
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 80, y: 68))
            p.addCurve(to: CGPoint(x: 96, y: 83), control1: CGPoint(x: 91, y: 66), control2: CGPoint(x: 100, y: 73))
            p.addLine(to: CGPoint(x: 91, y: 96))
            p.addQuadCurve(to: CGPoint(x: 105, y: 98), control: CGPoint(x: 101, y: 94))
            p.addQuadCurve(to: CGPoint(x: 88, y: 102), control: CGPoint(x: 113, y: 103))
            p.addQuadCurve(to: CGPoint(x: 85, y: 94), control: CGPoint(x: 81, y: 103))
            p.addLine(to: CGPoint(x: 89, y: 80))
            p.addQuadCurve(to: CGPoint(x: 80, y: 68), control: CGPoint(x: 83, y: 79))
            p.closeSubpath()
            p.move(to: CGPoint(x: 80, y: 72))
            p.addCurve(to: CGPoint(x: 80, y: 104), control1: CGPoint(x: 72, y: 86), control2: CGPoint(x: 85, y: 91))
            p.addQuadCurve(to: CGPoint(x: 76, y: 113), control: CGPoint(x: 75, y: 109))
            p.addQuadCurve(to: CGPoint(x: 95, y: 112), control: CGPoint(x: 88, y: 118))
            p.addLine(to: CGPoint(x: 86, y: 108))
            p.addCurve(to: CGPoint(x: 89, y: 83), control1: CGPoint(x: 87, y: 101), control2: CGPoint(x: 88, y: 93))
            p.addQuadCurve(to: CGPoint(x: 80, y: 72), control: CGPoint(x: 88, y: 76))
            p.closeSubpath()
        }
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 93, y: 39))
            p.addCurve(to: CGPoint(x: 73, y: 70), control1: CGPoint(x: 77, y: 42), control2: CGPoint(x: 65, y: 56))
            p.addQuadCurve(to: CGPoint(x: 90, y: 62), control: CGPoint(x: 84, y: 75))
            p.addQuadCurve(to: CGPoint(x: 93, y: 39), control: CGPoint(x: 97, y: 51))
            p.closeSubpath()
        }
        ellipse(Self.coral, x: 85, y: 15, width: 19, height: 19)
        box(Self.yellow, x: 20, y: 48, width: 38, height: 36, radius: 4)
        polygon(.white, CGPoint(x: 35, y: 54), CGPoint(x: 43, y: 54),
                CGPoint(x: 43, y: 67), CGPoint(x: 49, y: 67), CGPoint(x: 39, y: 77),
                CGPoint(x: 29, y: 67), CGPoint(x: 35, y: 67))
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 88, y: 43))
            p.addCurve(to: CGPoint(x: 56, y: 55), control1: CGPoint(x: 76, y: 38), control2: CGPoint(x: 65, y: 52))
            p.addQuadCurve(to: CGPoint(x: 52, y: 61), control: CGPoint(x: 48, y: 54))
            p.addCurve(to: CGPoint(x: 88, y: 43), control1: CGPoint(x: 67, y: 61), control2: CGPoint(x: 78, y: 48))
            p.closeSubpath()
            p.move(to: CGPoint(x: 87, y: 51))
            p.addCurve(to: CGPoint(x: 57, y: 72), control1: CGPoint(x: 86, y: 68), control2: CGPoint(x: 73, y: 77))
            p.addQuadCurve(to: CGPoint(x: 54, y: 66), control: CGPoint(x: 47, y: 71))
            p.addCurve(to: CGPoint(x: 87, y: 51), control1: CGPoint(x: 69, y: 71), control2: CGPoint(x: 81, y: 61))
            p.closeSubpath()
        }
    }
}
