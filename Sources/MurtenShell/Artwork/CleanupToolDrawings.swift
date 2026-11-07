import SwiftUI

extension ToolDrawing {
    func dockerCleaner() {
        // A low, braced pull makes the extracted container the focus.
        box(Self.blue, x: 8, y: 30, width: 33, height: 38, radius: 4)
        box(Self.teal, x: 8, y: 72, width: 33, height: 38, radius: 4)
        box(Self.yellow, x: 47, y: 76, width: 29, height: 34, radius: 4)
        stroke(.white, width: 3) { p in
            for x: CGFloat in [18, 30] {
                p.move(to: CGPoint(x: x, y: 36)); p.addLine(to: CGPoint(x: x, y: 62))
                p.move(to: CGPoint(x: x, y: 78)); p.addLine(to: CGPoint(x: x, y: 104))
            }
            for x: CGFloat in [56, 67] {
                p.move(to: CGPoint(x: x, y: 82)); p.addLine(to: CGPoint(x: x, y: 104))
            }
        }

        ellipse(Self.coral, x: 94, y: 47, width: 19, height: 19)
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 105, y: 70))
            p.addCurve(to: CGPoint(x: 86, y: 97), control1: CGPoint(x: 102, y: 83), control2: CGPoint(x: 96, y: 91))
            p.addQuadCurve(to: CGPoint(x: 101, y: 94), control: CGPoint(x: 94, y: 101))
            p.addCurve(to: CGPoint(x: 105, y: 70), control1: CGPoint(x: 113, y: 80), control2: CGPoint(x: 114, y: 73))
            p.closeSubpath()

            p.move(to: CGPoint(x: 96, y: 93))
            p.addCurve(to: CGPoint(x: 77, y: 99), control1: CGPoint(x: 90, y: 92), control2: CGPoint(x: 83, y: 94))
            p.addQuadCurve(to: CGPoint(x: 76, y: 106), control: CGPoint(x: 73, y: 102))
            p.addLine(to: CGPoint(x: 80, y: 111))
            p.addLine(to: CGPoint(x: 75, y: 114))
            p.addQuadCurve(to: CGPoint(x: 62, y: 119), control: CGPoint(x: 65, y: 114))
            p.addLine(to: CGPoint(x: 84, y: 119))
            p.addQuadCurve(to: CGPoint(x: 84, y: 112), control: CGPoint(x: 92, y: 117))
            p.addLine(to: CGPoint(x: 86, y: 105))
            p.addQuadCurve(to: CGPoint(x: 99, y: 100), control: CGPoint(x: 94, y: 102))
            p.closeSubpath()

            p.move(to: CGPoint(x: 98, y: 94))
            p.addCurve(to: CGPoint(x: 116, y: 104), control1: CGPoint(x: 110, y: 94), control2: CGPoint(x: 119, y: 98))
            p.addLine(to: CGPoint(x: 111, y: 113))
            p.addQuadCurve(to: CGPoint(x: 121, y: 119), control: CGPoint(x: 121, y: 115))
            p.addLine(to: CGPoint(x: 102, y: 119))
            p.addQuadCurve(to: CGPoint(x: 104, y: 112), control: CGPoint(x: 99, y: 117))
            p.addLine(to: CGPoint(x: 107, y: 103))
            p.addQuadCurve(to: CGPoint(x: 92, y: 99), control: CGPoint(x: 96, y: 104))
            p.closeSubpath()
        }
        stroke(Self.coral, width: 4.5) { p in
            p.move(to: CGPoint(x: 104, y: 75))
            p.addQuadCurve(to: CGPoint(x: 75, y: 80), control: CGPoint(x: 89, y: 83))
            p.addLine(to: CGPoint(x: 73, y: 77))
            p.move(to: CGPoint(x: 102, y: 79))
            p.addQuadCurve(to: CGPoint(x: 76, y: 96), control: CGPoint(x: 90, y: 94))
            p.addLine(to: CGPoint(x: 76, y: 93))
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
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 105, y: 69))
            p.addQuadCurve(to: CGPoint(x: 92, y: 91), control: CGPoint(x: 97, y: 76))
            p.addLine(to: CGPoint(x: 79, y: 112))
            p.addQuadCurve(to: CGPoint(x: 74, y: 119), control: CGPoint(x: 72, y: 116))
            p.addLine(to: CGPoint(x: 91, y: 119))
            p.addQuadCurve(to: CGPoint(x: 88, y: 113), control: CGPoint(x: 98, y: 118))
            p.addLine(to: CGPoint(x: 104, y: 94))
            p.addQuadCurve(to: CGPoint(x: 113, y: 70), control: CGPoint(x: 112, y: 78))
            p.closeSubpath()

            p.move(to: CGPoint(x: 111, y: 69))
            p.addCurve(to: CGPoint(x: 118, y: 109), control1: CGPoint(x: 116, y: 81), control2: CGPoint(x: 115, y: 95))
            p.addQuadCurve(to: CGPoint(x: 121, y: 119), control: CGPoint(x: 122, y: 116))
            p.addLine(to: CGPoint(x: 108, y: 119))
            p.addQuadCurve(to: CGPoint(x: 110, y: 112), control: CGPoint(x: 105, y: 117))
            p.addLine(to: CGPoint(x: 108, y: 95))
            p.addCurve(to: CGPoint(x: 103, y: 72), control1: CGPoint(x: 106, y: 84), control2: CGPoint(x: 100, y: 79))
            p.closeSubpath()
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
