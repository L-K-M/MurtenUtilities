import SwiftUI

extension ToolDrawing {
    func permissionCheckup() {
        // The lock stays closed while the kneeling inspector checks its keyhole.
        stroke(Self.blue, width: 6) { p in
            p.move(to: CGPoint(x: 22, y: 55))
            p.addLine(to: CGPoint(x: 22, y: 38))
            p.addCurve(to: CGPoint(x: 51, y: 38), control1: CGPoint(x: 22, y: 18), control2: CGPoint(x: 51, y: 18))
            p.addLine(to: CGPoint(x: 51, y: 55))
        }
        box(Self.yellow, x: 12, y: 51, width: 49, height: 51, radius: 7)
        ellipse(.white, x: 32, y: 70, width: 10, height: 10)
        polygon(.white, CGPoint(x: 35, y: 77), CGPoint(x: 39, y: 77),
                CGPoint(x: 43, y: 89), CGPoint(x: 31, y: 89))

        ellipse(Self.blue, x: 82, y: 43, width: 19, height: 19)
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 96, y: 65))
            p.addCurve(to: CGPoint(x: 79, y: 91), control1: CGPoint(x: 80, y: 67), control2: CGPoint(x: 74, y: 81))
            p.addQuadCurve(to: CGPoint(x: 98, y: 91), control: CGPoint(x: 91, y: 97))
            p.addQuadCurve(to: CGPoint(x: 96, y: 65), control: CGPoint(x: 102, y: 79))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            // One knee is down; the other foot braces beside the lock.
            p.move(to: CGPoint(x: 86, y: 91))
            p.addQuadCurve(to: CGPoint(x: 77, y: 107), control: CGPoint(x: 81, y: 99))
            p.addQuadCurve(to: CGPoint(x: 64, y: 113), control: CGPoint(x: 67, y: 107))
            p.addLine(to: CGPoint(x: 84, y: 113))
            p.addQuadCurve(to: CGPoint(x: 94, y: 94), control: CGPoint(x: 83, y: 102))
            p.closeSubpath()
            p.move(to: CGPoint(x: 97, y: 89))
            p.addQuadCurve(to: CGPoint(x: 115, y: 101), control: CGPoint(x: 114, y: 90))
            p.addLine(to: CGPoint(x: 111, y: 108))
            p.addQuadCurve(to: CGPoint(x: 120, y: 113), control: CGPoint(x: 119, y: 107))
            p.addLine(to: CGPoint(x: 102, y: 113))
            p.addQuadCurve(to: CGPoint(x: 105, y: 103), control: CGPoint(x: 101, y: 108))
            p.addQuadCurve(to: CGPoint(x: 97, y: 89), control: CGPoint(x: 95, y: 98))
            p.closeSubpath()
            p.move(to: CGPoint(x: 87, y: 68))
            p.addCurve(to: CGPoint(x: 64, y: 95), control1: CGPoint(x: 85, y: 88), control2: CGPoint(x: 72, y: 89))
            p.addQuadCurve(to: CGPoint(x: 61, y: 92), control: CGPoint(x: 60, y: 98))
            p.addCurve(to: CGPoint(x: 87, y: 68), control1: CGPoint(x: 74, y: 82), control2: CGPoint(x: 79, y: 84))
            p.closeSubpath()
        }
        stroke(Self.teal, width: 4) { p in
            p.move(to: CGPoint(x: 83, y: 70))
            p.addQuadCurve(to: CGPoint(x: 57, y: 77), control: CGPoint(x: 70, y: 66))
        }
        stroke(Self.coral, width: 5) { p in
            p.addEllipse(in: CGRect(x: 26, y: 66, width: 22, height: 22))
            p.move(to: CGPoint(x: 45, y: 85))
            p.addLine(to: CGPoint(x: 63, y: 95))
        }
    }

    func shortcutDetective() {
        box(Self.teal, x: 9, y: 67, width: 111, height: 48, radius: 8)
        for row in 0..<2 {
            for column in 0..<3 {
                let color: Color = row == 1 && column == 1 ? Self.yellow : .white
                box(color, x: 15 + CGFloat(column) * 35, y: 74 + CGFloat(row) * 20,
                    width: 28, height: 14, radius: 3)
            }
        }

        // The detective lounges across the keyboard rather than beside it.
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 57, y: 51))
            p.addQuadCurve(to: CGPoint(x: 34, y: 56), control: CGPoint(x: 45, y: 55))
            p.addLine(to: CGPoint(x: 39, y: 29))
            p.addQuadCurve(to: CGPoint(x: 25, y: 17), control: CGPoint(x: 39, y: 22))
            p.addQuadCurve(to: CGPoint(x: 23, y: 21), control: CGPoint(x: 17, y: 14))
            p.addLine(to: CGPoint(x: 32, y: 29))
            p.addLine(to: CGPoint(x: 28, y: 59))
            p.addQuadCurve(to: CGPoint(x: 57, y: 57), control: CGPoint(x: 39, y: 63))
            p.closeSubpath()
            p.move(to: CGPoint(x: 55, y: 57))
            p.addQuadCurve(to: CGPoint(x: 23, y: 57), control: CGPoint(x: 38, y: 59))
            p.addQuadCurve(to: CGPoint(x: 8, y: 69), control: CGPoint(x: 17, y: 52))
            p.addQuadCurve(to: CGPoint(x: 23, y: 63), control: CGPoint(x: 6, y: 76))
            p.addQuadCurve(to: CGPoint(x: 57, y: 65), control: CGPoint(x: 41, y: 68))
            p.closeSubpath()
        }
        fill(Self.yellow) { p in
            p.move(to: CGPoint(x: 76, y: 46))
            p.addQuadCurve(to: CGPoint(x: 56, y: 49), control: CGPoint(x: 67, y: 43))
            p.addQuadCurve(to: CGPoint(x: 45, y: 64), control: CGPoint(x: 48, y: 50))
            p.addQuadCurve(to: CGPoint(x: 70, y: 63), control: CGPoint(x: 57, y: 68))
            p.addQuadCurve(to: CGPoint(x: 76, y: 46), control: CGPoint(x: 73, y: 56))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 101, y: 43))
            p.addCurve(to: CGPoint(x: 72, y: 50), control1: CGPoint(x: 90, y: 40), control2: CGPoint(x: 80, y: 42))
            p.addQuadCurve(to: CGPoint(x: 68, y: 65), control: CGPoint(x: 64, y: 55))
            p.addQuadCurve(to: CGPoint(x: 86, y: 59), control: CGPoint(x: 79, y: 64))
            p.addQuadCurve(to: CGPoint(x: 101, y: 43), control: CGPoint(x: 97, y: 52))
            p.closeSubpath()
            // An elbow props up the head while the free arm lowers the lens.
            p.move(to: CGPoint(x: 101, y: 47))
            p.addQuadCurve(to: CGPoint(x: 116, y: 63), control: CGPoint(x: 108, y: 61))
            p.addQuadCurve(to: CGPoint(x: 112, y: 43), control: CGPoint(x: 116, y: 54))
            p.addLine(to: CGPoint(x: 109, y: 42))
            p.addQuadCurve(to: CGPoint(x: 109, y: 55), control: CGPoint(x: 110, y: 47))
            p.addQuadCurve(to: CGPoint(x: 101, y: 47), control: CGPoint(x: 105, y: 51))
            p.closeSubpath()
            p.move(to: CGPoint(x: 84, y: 50))
            p.addCurve(to: CGPoint(x: 66, y: 78), control1: CGPoint(x: 66, y: 57), control2: CGPoint(x: 60, y: 65))
            p.addQuadCurve(to: CGPoint(x: 70, y: 79), control: CGPoint(x: 65, y: 84))
            p.addCurve(to: CGPoint(x: 84, y: 50), control1: CGPoint(x: 65, y: 68), control2: CGPoint(x: 78, y: 64))
            p.closeSubpath()
        }
        ellipse(Self.blue, x: 98, y: 20, width: 20, height: 20)
        stroke(Self.coral, width: 5) { p in
            p.move(to: CGPoint(x: 67, y: 80)); p.addLine(to: CGPoint(x: 65, y: 87))
            p.addEllipse(in: CGRect(x: 50, y: 87, width: 28, height: 28))
        }
    }

    func networkAccess() {
        stroke(Self.teal, width: 3) { p in
            p.move(to: CGPoint(x: 63, y: 26)); p.addLine(to: CGPoint(x: 63, y: 35))
            p.move(to: CGPoint(x: 41, y: 40)); p.addLine(to: CGPoint(x: 63, y: 32))
            p.addLine(to: CGPoint(x: 84, y: 40))
        }
        box(Self.blue, x: 56, y: 12, width: 15, height: 14, radius: 3)
        box(Self.teal, x: 34, y: 35, width: 14, height: 12, radius: 3)
        box(Self.lime, x: 77, y: 35, width: 14, height: 12, radius: 3)

        // Two helpers meet at the connector: the connection is the action.
        ellipse(Self.teal, x: 15, y: 40, width: 17, height: 17)
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 23, y: 61))
            p.addQuadCurve(to: CGPoint(x: 20, y: 87), control: CGPoint(x: 14, y: 74))
            p.addQuadCurve(to: CGPoint(x: 37, y: 85), control: CGPoint(x: 31, y: 93))
            p.addQuadCurve(to: CGPoint(x: 23, y: 61), control: CGPoint(x: 39, y: 68))
            p.closeSubpath()
        }
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 22, y: 87))
            p.addQuadCurve(to: CGPoint(x: 13, y: 113), control: CGPoint(x: 19, y: 103))
            p.addQuadCurve(to: CGPoint(x: 29, y: 91), control: CGPoint(x: 26, y: 102))
            p.closeSubpath()
            p.move(to: CGPoint(x: 33, y: 87))
            p.addQuadCurve(to: CGPoint(x: 36, y: 108), control: CGPoint(x: 29, y: 102))
            p.addLine(to: CGPoint(x: 44, y: 113)); p.addLine(to: CGPoint(x: 30, y: 113))
            p.addQuadCurve(to: CGPoint(x: 33, y: 87), control: CGPoint(x: 25, y: 98))
            p.closeSubpath()
            p.move(to: CGPoint(x: 31, y: 64))
            p.addCurve(to: CGPoint(x: 55, y: 80), control1: CGPoint(x: 35, y: 77), control2: CGPoint(x: 42, y: 72))
            p.addQuadCurve(to: CGPoint(x: 53, y: 84), control: CGPoint(x: 57, y: 85))
            p.addCurve(to: CGPoint(x: 31, y: 64), control1: CGPoint(x: 34, y: 82), control2: CGPoint(x: 27, y: 79))
            p.closeSubpath()
        }
        ellipse(Self.blue, x: 97, y: 49, width: 17, height: 17)
        fill(Self.yellow) { p in
            p.move(to: CGPoint(x: 102, y: 69))
            p.addQuadCurve(to: CGPoint(x: 86, y: 91), control: CGPoint(x: 89, y: 71))
            p.addQuadCurve(to: CGPoint(x: 104, y: 92), control: CGPoint(x: 99, y: 99))
            p.addQuadCurve(to: CGPoint(x: 102, y: 69), control: CGPoint(x: 111, y: 81))
            p.closeSubpath()
        }
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 93, y: 91))
            p.addQuadCurve(to: CGPoint(x: 91, y: 108), control: CGPoint(x: 88, y: 102))
            p.addLine(to: CGPoint(x: 102, y: 113)); p.addLine(to: CGPoint(x: 87, y: 113))
            p.addQuadCurve(to: CGPoint(x: 93, y: 91), control: CGPoint(x: 80, y: 103))
            p.closeSubpath()
            p.move(to: CGPoint(x: 104, y: 91))
            p.addQuadCurve(to: CGPoint(x: 114, y: 106), control: CGPoint(x: 107, y: 100))
            p.addLine(to: CGPoint(x: 121, y: 108))
            p.addQuadCurve(to: CGPoint(x: 104, y: 91), control: CGPoint(x: 113, y: 116))
            p.closeSubpath()
            p.move(to: CGPoint(x: 98, y: 72))
            p.addCurve(to: CGPoint(x: 74, y: 79), control1: CGPoint(x: 88, y: 70), control2: CGPoint(x: 83, y: 75))
            p.addQuadCurve(to: CGPoint(x: 74, y: 84), control: CGPoint(x: 68, y: 80))
            p.addCurve(to: CGPoint(x: 98, y: 72), control1: CGPoint(x: 89, y: 83), control2: CGPoint(x: 93, y: 83))
            p.closeSubpath()
        }
        stroke(Self.teal, width: 3) { p in
            p.move(to: CGPoint(x: 54, y: 82))
            p.addCurve(to: CGPoint(x: 39, y: 103), control1: CGPoint(x: 47, y: 88), control2: CGPoint(x: 53, y: 101))
            p.move(to: CGPoint(x: 74, y: 82))
            p.addCurve(to: CGPoint(x: 84, y: 105), control1: CGPoint(x: 90, y: 86), control2: CGPoint(x: 76, y: 99))
        }
        box(Self.teal, x: 53, y: 76, width: 11, height: 11, radius: 2)
        box(Self.blue, x: 64, y: 76, width: 11, height: 11, radius: 2)
        box(Self.coral, x: 62, y: 75, width: 4, height: 13, radius: 1)
    }
}
