import SwiftUI

extension ToolDrawing {
    func runnerManager() {
        // A full sprint above three linked build stages.
        stroke(Self.blue, width: 3) { p in
            p.move(to: CGPoint(x: 27, y: 106)); p.addLine(to: CGPoint(x: 102, y: 106))
        }
        box(Self.teal, x: 7, y: 96, width: 22, height: 22, radius: 4)
        box(Self.yellow, x: 53, y: 96, width: 22, height: 22, radius: 4)
        box(Self.lime, x: 99, y: 96, width: 22, height: 22, radius: 4)
        stroke(.white, width: 3) { p in
            p.move(to: CGPoint(x: 104, y: 107)); p.addLine(to: CGPoint(x: 109, y: 112))
            p.addLine(to: CGPoint(x: 117, y: 102))
        }

        ellipse(Self.blue, x: 87, y: 9, width: 19, height: 19)
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 94, y: 32))
            p.addCurve(to: CGPoint(x: 58, y: 61), control1: CGPoint(x: 78, y: 31), control2: CGPoint(x: 63, y: 43))
            p.addQuadCurve(to: CGPoint(x: 80, y: 55), control: CGPoint(x: 70, y: 64))
            p.addQuadCurve(to: CGPoint(x: 94, y: 32), control: CGPoint(x: 86, y: 43))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 77, y: 35))
            p.addCurve(to: CGPoint(x: 51, y: 30), control1: CGPoint(x: 62, y: 44), control2: CGPoint(x: 59, y: 26))
            p.addQuadCurve(to: CGPoint(x: 33, y: 46), control: CGPoint(x: 42, y: 31))
            p.addQuadCurve(to: CGPoint(x: 52, y: 37), control: CGPoint(x: 45, y: 42))
            p.addCurve(to: CGPoint(x: 77, y: 35), control1: CGPoint(x: 62, y: 52), control2: CGPoint(x: 69, y: 46))
            p.closeSubpath()

            p.move(to: CGPoint(x: 93, y: 37))
            p.addQuadCurve(to: CGPoint(x: 111, y: 48), control: CGPoint(x: 101, y: 58))
            p.addQuadCurve(to: CGPoint(x: 120, y: 29), control: CGPoint(x: 119, y: 39))
            p.addQuadCurve(to: CGPoint(x: 109, y: 40), control: CGPoint(x: 111, y: 32))
            p.addQuadCurve(to: CGPoint(x: 93, y: 37), control: CGPoint(x: 101, y: 44))
            p.closeSubpath()

            p.move(to: CGPoint(x: 61, y: 62))
            p.addQuadCurve(to: CGPoint(x: 43, y: 75), control: CGPoint(x: 58, y: 71))
            p.addLine(to: CGPoint(x: 18, y: 58))
            p.addQuadCurve(to: CGPoint(x: 7, y: 61), control: CGPoint(x: 10, y: 53))
            p.addLine(to: CGPoint(x: 39, y: 85))
            p.addQuadCurve(to: CGPoint(x: 68, y: 66), control: CGPoint(x: 52, y: 91))
            p.closeSubpath()

            p.move(to: CGPoint(x: 78, y: 59))
            p.addQuadCurve(to: CGPoint(x: 91, y: 73), control: CGPoint(x: 83, y: 63))
            p.addQuadCurve(to: CGPoint(x: 117, y: 85), control: CGPoint(x: 109, y: 74))
            p.addQuadCurve(to: CGPoint(x: 91, y: 84), control: CGPoint(x: 111, y: 89))
            p.addQuadCurve(to: CGPoint(x: 67, y: 65), control: CGPoint(x: 73, y: 81))
            p.closeSubpath()
        }
    }

    func systemMonitor() {
        // The wide display leads; its operator sits at the right of the desk.
        box(Self.blue, x: 7, y: 20, width: 79, height: 57, radius: 7)
        box(.white, x: 12, y: 25, width: 69, height: 46, radius: 4)
        box(Self.teal, x: 17, y: 30, width: 59, height: 35, radius: 2)
        stroke(.white, width: 2.5) { p in
            p.move(to: CGPoint(x: 21, y: 48)); p.addLine(to: CGPoint(x: 31, y: 48))
            p.addLine(to: CGPoint(x: 37, y: 36)); p.addLine(to: CGPoint(x: 47, y: 59))
            p.addLine(to: CGPoint(x: 55, y: 45)); p.addLine(to: CGPoint(x: 71, y: 45))
        }
        polygon(Self.yellow, CGPoint(x: 40, y: 77), CGPoint(x: 51, y: 77),
                CGPoint(x: 55, y: 88), CGPoint(x: 65, y: 93),
                CGPoint(x: 27, y: 93), CGPoint(x: 37, y: 88))
        stroke(Self.blue, width: 4) { p in
            p.move(to: CGPoint(x: 7, y: 98)); p.addLine(to: CGPoint(x: 88, y: 98))
            p.move(to: CGPoint(x: 13, y: 100)); p.addLine(to: CGPoint(x: 13, y: 118))
            p.move(to: CGPoint(x: 82, y: 100)); p.addLine(to: CGPoint(x: 82, y: 118))
        }
        stroke(Self.coral, width: 3) { p in
            p.move(to: CGPoint(x: 121, y: 80)); p.addLine(to: CGPoint(x: 121, y: 99))
            p.addLine(to: CGPoint(x: 104, y: 99))
            p.move(to: CGPoint(x: 119, y: 101)); p.addLine(to: CGPoint(x: 119, y: 119))
        }

        ellipse(Self.coral, x: 98, y: 48, width: 19, height: 19)
        fill(Self.yellow) { p in
            p.move(to: CGPoint(x: 106, y: 72))
            p.addCurve(to: CGPoint(x: 97, y: 95), control1: CGPoint(x: 96, y: 75), control2: CGPoint(x: 99, y: 84))
            p.addQuadCurve(to: CGPoint(x: 114, y: 94), control: CGPoint(x: 110, y: 98))
            p.addQuadCurve(to: CGPoint(x: 106, y: 72), control: CGPoint(x: 118, y: 79))
            p.closeSubpath()
        }
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 101, y: 75))
            p.addQuadCurve(to: CGPoint(x: 89, y: 79), control: CGPoint(x: 94, y: 87))
            p.addLine(to: CGPoint(x: 75, y: 66))
            p.addQuadCurve(to: CGPoint(x: 72, y: 61), control: CGPoint(x: 71, y: 67))
            p.addQuadCurve(to: CGPoint(x: 81, y: 65), control: CGPoint(x: 77, y: 58))
            p.addLine(to: CGPoint(x: 92, y: 73))
            p.addQuadCurve(to: CGPoint(x: 101, y: 75), control: CGPoint(x: 96, y: 72))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 108, y: 95))
            p.addQuadCurve(to: CGPoint(x: 96, y: 104), control: CGPoint(x: 104, y: 104))
            p.addLine(to: CGPoint(x: 94, y: 115))
            p.addLine(to: CGPoint(x: 106, y: 120))
            p.addQuadCurve(to: CGPoint(x: 87, y: 118), control: CGPoint(x: 89, y: 123))
            p.addLine(to: CGPoint(x: 87, y: 101))
            p.addQuadCurve(to: CGPoint(x: 108, y: 95), control: CGPoint(x: 91, y: 93))
            p.closeSubpath()
        }
    }
}
