import SwiftUI

extension ToolDrawing {
    func permissionCheckup() {
        leaningFigure(limbs: Self.blue, shirt: Self.coral, reaches: CGPoint(x: 62, y: 59))
        magnifier(Self.teal, x: 77, y: 43)
        stroke(Self.yellow, width: 6) { p in
            p.move(to: CGPoint(x: 87, y: 77))
            p.addLine(to: CGPoint(x: 87, y: 67))
            p.addCurve(to: CGPoint(x: 112, y: 67), control1: CGPoint(x: 87, y: 48), control2: CGPoint(x: 112, y: 48))
            p.addLine(to: CGPoint(x: 112, y: 77))
        }
        box(Self.yellow, x: 80, y: 75, width: 39, height: 37, radius: 6)
        ellipse(.white, x: 95, y: 84, width: 10, height: 10)
        polygon(.white, CGPoint(x: 97, y: 91), CGPoint(x: 103, y: 91),
                CGPoint(x: 106, y: 103), CGPoint(x: 94, y: 103))
    }

    func shortcutDetective() {
        leaningFigure(limbs: Self.teal, shirt: Self.yellow, reaches: CGPoint(x: 68, y: 61))
        box(Self.blue, x: 65, y: 72, width: 57, height: 36, radius: 5)
        for row in 0..<2 {
            for column in 0..<4 {
                box(.white, x: 71 + CGFloat(column) * 12, y: 78 + CGFloat(row) * 10,
                    width: 8, height: 6, radius: 1)
            }
        }
        box(Self.yellow, x: 82, y: 98, width: 23, height: 4, radius: 1)
        magnifier(Self.coral, x: 83, y: 45, radius: 15)
    }

    func networkAccess() {
        standingFigure(limbs: Self.blue, shirt: Self.yellow)
        stroke(Self.teal, width: 4) { p in
            p.move(to: CGPoint(x: 88, y: 44)); p.addLine(to: CGPoint(x: 88, y: 78))
            p.move(to: CGPoint(x: 72, y: 90)); p.addLine(to: CGPoint(x: 88, y: 78))
            p.addLine(to: CGPoint(x: 110, y: 90))
        }
        box(Self.teal, x: 73, y: 23, width: 30, height: 24, radius: 4)
        box(.white, x: 78, y: 28, width: 20, height: 14, radius: 1)
        box(Self.coral, x: 61, y: 87, width: 26, height: 22, radius: 4)
        box(.white, x: 66, y: 92, width: 16, height: 12, radius: 1)
        box(Self.lime, x: 97, y: 87, width: 26, height: 22, radius: 4)
        box(.white, x: 102, y: 92, width: 16, height: 12, radius: 1)
        stroke(Self.yellow, width: 5) { p in
            p.move(to: CGPoint(x: 57, y: 55))
            p.addCurve(to: CGPoint(x: 81, y: 65), control1: CGPoint(x: 65, y: 78), control2: CGPoint(x: 65, y: 65))
        }
        box(Self.coral, x: 79, y: 59, width: 11, height: 12, radius: 2)
    }
}
