import SwiftUI

extension ToolDrawing {
    func dockerCleaner() {
        // The containers and both planted feet share the same floor.
        box(Self.blue, x: 8, y: 41, width: 33, height: 38, radius: 4)
        box(Self.teal, x: 8, y: 79, width: 33, height: 38, radius: 4)
        box(Self.yellow, x: 47, y: 83, width: 29, height: 34, radius: 4)
        stroke(.white, width: 3) { p in
            for x: CGFloat in [18, 30] {
                p.move(to: CGPoint(x: x, y: 47)); p.addLine(to: CGPoint(x: x, y: 73))
                p.move(to: CGPoint(x: x, y: 85)); p.addLine(to: CGPoint(x: x, y: 111))
            }
            for x: CGFloat in [56, 67] {
                p.move(to: CGPoint(x: x, y: 89)); p.addLine(to: CGPoint(x: x, y: 111))
            }
        }
        stroke(Self.coral, width: 7) { p in
            p.move(to: CGPoint(x: 100, y: 92))
            p.addLine(to: CGPoint(x: 86, y: 102))
            p.addLine(to: CGPoint(x: 83, y: 114))
            p.addLine(to: CGPoint(x: 72, y: 114))
            p.move(to: CGPoint(x: 104, y: 92))
            p.addLine(to: CGPoint(x: 113, y: 102))
            p.addLine(to: CGPoint(x: 113, y: 114))
            p.addLine(to: CGPoint(x: 104, y: 114))
        }
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 99, y: 67))
            p.addCurve(to: CGPoint(x: 100, y: 96), control1: CGPoint(x: 94, y: 76), control2: CGPoint(x: 97, y: 88))
            p.addQuadCurve(to: CGPoint(x: 109, y: 93), control: CGPoint(x: 108, y: 99))
            p.addCurve(to: CGPoint(x: 105, y: 67), control1: CGPoint(x: 111, y: 83), control2: CGPoint(x: 110, y: 73))
            p.closeSubpath()
        }
        ellipse(Self.coral, x: 95, y: 45, width: 17, height: 17)
        stroke(Self.coral, width: 4.5) { p in
            p.move(to: CGPoint(x: 99, y: 71))
            p.addLine(to: CGPoint(x: 89, y: 82))
            p.addLine(to: CGPoint(x: 76, y: 87))
            p.move(to: CGPoint(x: 105, y: 74))
            p.addLine(to: CGPoint(x: 95, y: 91))
            p.addLine(to: CGPoint(x: 76, y: 98))
        }
    }

    func developerCleanup() {
        document(Self.coral, x: 8, y: 83, size: 11)
        document(Self.coral, x: 19, y: 94, size: 11)
        document(Self.lime, x: 8, y: 104, size: 10)

        ellipse(Self.teal, x: 65, y: 19, width: 19, height: 19)
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 81, y: 43))
            p.addCurve(to: CGPoint(x: 111, y: 63), control1: CGPoint(x: 87, y: 41), control2: CGPoint(x: 100, y: 48))
            p.addQuadCurve(to: CGPoint(x: 102, y: 74), control: CGPoint(x: 115, y: 74))
            p.addCurve(to: CGPoint(x: 81, y: 43), control1: CGPoint(x: 98, y: 61), control2: CGPoint(x: 89, y: 55))
            p.closeSubpath()
        }
        stroke(Self.teal, width: 7) { p in
            p.move(to: CGPoint(x: 104, y: 69))
            p.addLine(to: CGPoint(x: 96, y: 92))
            p.addLine(to: CGPoint(x: 85, y: 116))
            p.addLine(to: CGPoint(x: 75, y: 116))
            p.move(to: CGPoint(x: 109, y: 69))
            p.addLine(to: CGPoint(x: 116, y: 92))
            p.addLine(to: CGPoint(x: 116, y: 116))
            p.addLine(to: CGPoint(x: 106, y: 116))
        }
        stroke(Self.teal, width: 4.5) { p in
            p.move(to: CGPoint(x: 83, y: 47))
            p.addQuadCurve(to: CGPoint(x: 65, y: 64), control: CGPoint(x: 78, y: 61))
            p.move(to: CGPoint(x: 89, y: 50))
            p.addQuadCurve(to: CGPoint(x: 73, y: 72), control: CGPoint(x: 89, y: 67))
            p.addLine(to: CGPoint(x: 61, y: 70))
        }

        // The long sweep runs against the bend of the figure's body.
        stroke(Self.blue, width: 4) { p in
            p.move(to: CGPoint(x: 70, y: 57)); p.addLine(to: CGPoint(x: 33, y: 103))
        }
        fill(Self.yellow) { p in
            p.move(to: CGPoint(x: 31, y: 100))
            p.addLine(to: CGPoint(x: 37, y: 104))
            p.addQuadCurve(to: CGPoint(x: 50, y: 118), control: CGPoint(x: 42, y: 113))
            p.addQuadCurve(to: CGPoint(x: 18, y: 118), control: CGPoint(x: 35, y: 123))
            p.addQuadCurve(to: CGPoint(x: 31, y: 100), control: CGPoint(x: 28, y: 106))
            p.closeSubpath()
        }
        stroke(.white, width: 2) { p in
            p.move(to: CGPoint(x: 31, y: 108)); p.addLine(to: CGPoint(x: 27, y: 118))
            p.move(to: CGPoint(x: 37, y: 108)); p.addLine(to: CGPoint(x: 41, y: 118))
        }
    }
}
