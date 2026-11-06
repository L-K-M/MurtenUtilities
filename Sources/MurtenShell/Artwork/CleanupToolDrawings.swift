import SwiftUI

extension ToolDrawing {
    func dockerCleaner() {
        leaningFigure(limbs: Self.blue, shirt: Self.coral, reaches: CGPoint(x: 78, y: 53))
        // A stack of containers, lifted clear of its tray.
        box(Self.teal, x: 66, y: 78, width: 54, height: 32, radius: 5)
        box(.white, x: 71, y: 78, width: 44, height: 24, radius: 2)
        box(Self.yellow, x: 77, y: 53, width: 35, height: 32, radius: 3)
        polygon(Self.coral, CGPoint(x: 77, y: 53), CGPoint(x: 87, y: 44),
                CGPoint(x: 120, y: 44), CGPoint(x: 112, y: 53))
        polygon(Self.lime, CGPoint(x: 112, y: 53), CGPoint(x: 120, y: 44),
                CGPoint(x: 120, y: 76), CGPoint(x: 112, y: 85))
        stroke(.white, width: 3) { p in
            p.move(to: CGPoint(x: 89, y: 60)); p.addLine(to: CGPoint(x: 89, y: 77))
            p.move(to: CGPoint(x: 100, y: 60)); p.addLine(to: CGPoint(x: 100, y: 77))
        }
        polygon(Self.teal, CGPoint(x: 69, y: 62), CGPoint(x: 63, y: 62),
                CGPoint(x: 63, y: 35), CGPoint(x: 57, y: 35),
                CGPoint(x: 66, y: 24), CGPoint(x: 75, y: 35), CGPoint(x: 69, y: 35))
    }

    func developerCleanup() {
        leaningFigure(limbs: Self.teal, shirt: Self.blue, reaches: CGPoint(x: 56, y: 68))
        document(Self.coral, x: 89, y: 64, size: 17)
        document(Self.coral, x: 75, y: 88, size: 17)
        document(Self.lime, x: 104, y: 89, size: 17)
        stroke(Self.teal, width: 4) { p in
            p.move(to: CGPoint(x: 32, y: 40)); p.addLine(to: CGPoint(x: 73, y: 88))
        }
        fill(Self.yellow) { p in
            p.move(to: CGPoint(x: 67, y: 84))
            p.addQuadCurve(to: CGPoint(x: 48, y: 113), control: CGPoint(x: 62, y: 102))
            p.addQuadCurve(to: CGPoint(x: 91, y: 117), control: CGPoint(x: 69, y: 123))
            p.addQuadCurve(to: CGPoint(x: 78, y: 86), control: CGPoint(x: 82, y: 98))
            p.closeSubpath()
        }
        stroke(.white, width: 2.5) { p in
            p.move(to: CGPoint(x: 67, y: 99)); p.addLine(to: CGPoint(x: 61, y: 116))
            p.move(to: CGPoint(x: 73, y: 100)); p.addLine(to: CGPoint(x: 73, y: 118))
            p.move(to: CGPoint(x: 79, y: 100)); p.addLine(to: CGPoint(x: 84, y: 117))
        }
    }
}
