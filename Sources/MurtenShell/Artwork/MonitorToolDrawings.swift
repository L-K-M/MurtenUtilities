import SwiftUI

extension ToolDrawing {
    func runnerManager() {
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

        // Shoulder–elbow–wrist and hip–knee–ankle chains keep the sprint readable.
        stroke(Self.blue, width: 6) { p in
            p.move(to: CGPoint(x: 82, y: 36))
            p.addLine(to: CGPoint(x: 65, y: 27))
            p.addLine(to: CGPoint(x: 52, y: 40))
            p.move(to: CGPoint(x: 87, y: 36))
            p.addLine(to: CGPoint(x: 102, y: 49))
            p.addLine(to: CGPoint(x: 115, y: 37))
        }
        stroke(Self.blue, width: 7.5) { p in
            p.move(to: CGPoint(x: 64, y: 64))
            p.addLine(to: CGPoint(x: 43, y: 78))
            p.addLine(to: CGPoint(x: 21, y: 63))
            p.addLine(to: CGPoint(x: 12, y: 67))
            p.move(to: CGPoint(x: 67, y: 63))
            p.addLine(to: CGPoint(x: 87, y: 63))
            p.addLine(to: CGPoint(x: 79, y: 85))
            p.addLine(to: CGPoint(x: 91, y: 88))
        }
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 94, y: 32))
            p.addCurve(to: CGPoint(x: 58, y: 61), control1: CGPoint(x: 78, y: 31), control2: CGPoint(x: 63, y: 43))
            p.addQuadCurve(to: CGPoint(x: 70, y: 66), control: CGPoint(x: 62, y: 65))
            p.addQuadCurve(to: CGPoint(x: 85, y: 49), control: CGPoint(x: 79, y: 58))
            p.addQuadCurve(to: CGPoint(x: 94, y: 32), control: CGPoint(x: 89, y: 40))
            p.closeSubpath()
        }
        ellipse(Self.blue, x: 87, y: 9, width: 19, height: 19)
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
                CGPoint(x: 55, y: 88), CGPoint(x: 65, y: 96),
                CGPoint(x: 27, y: 96), CGPoint(x: 37, y: 88))
        stroke(Self.blue, width: 4) { p in
            p.move(to: CGPoint(x: 7, y: 98)); p.addLine(to: CGPoint(x: 88, y: 98))
            p.move(to: CGPoint(x: 13, y: 100)); p.addLine(to: CGPoint(x: 13, y: 118))
            p.move(to: CGPoint(x: 76, y: 100)); p.addLine(to: CGPoint(x: 76, y: 118))
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
        // The visible shoe points left, in the operator's viewing direction.
        stroke(Self.blue, width: 6) { p in
            p.move(to: CGPoint(x: 108, y: 95))
            p.addLine(to: CGPoint(x: 95, y: 100))
            p.addLine(to: CGPoint(x: 95, y: 117))
            p.addLine(to: CGPoint(x: 87, y: 117))
        }
    }
}
