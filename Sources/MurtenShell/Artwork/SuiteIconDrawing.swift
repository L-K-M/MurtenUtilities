import SwiftUI

extension ToolDrawing {
    /// A little Mac workshop: the helper and computer form one silhouette.
    func suiteIcon() {
        stroke(Self.teal, width: 4) { p in
            p.move(to: CGPoint(x: 29, y: 101))
            p.addCurve(to: CGPoint(x: 27, y: 80), control1: CGPoint(x: 4, y: 109), control2: CGPoint(x: 3, y: 77))
        }
        polygon(Self.teal, CGPoint(x: 27, y: 68), CGPoint(x: 43, y: 54),
                CGPoint(x: 47, y: 119), CGPoint(x: 27, y: 110))
        fill(Self.blue) { p in
            p.move(to: CGPoint(x: 47, y: 54))
            p.addLine(to: CGPoint(x: 99, y: 47))
            p.addQuadCurve(to: CGPoint(x: 106, y: 53), control: CGPoint(x: 105, y: 46))
            p.addLine(to: CGPoint(x: 116, y: 114))
            p.addLine(to: CGPoint(x: 47, y: 120))
            p.addLine(to: CGPoint(x: 40, y: 62))
            p.addQuadCurve(to: CGPoint(x: 47, y: 54), control: CGPoint(x: 39, y: 56))
            p.closeSubpath()
        }
        let ivory = Color(red: 0.985, green: 0.982, blue: 0.965)
        fill(ivory) { p in
            p.move(to: CGPoint(x: 57, y: 66))
            p.addLine(to: CGPoint(x: 93, y: 61))
            p.addQuadCurve(to: CGPoint(x: 98, y: 65), control: CGPoint(x: 97, y: 60))
            p.addLine(to: CGPoint(x: 102, y: 91))
            p.addQuadCurve(to: CGPoint(x: 98, y: 96), control: CGPoint(x: 103, y: 95))
            p.addLine(to: CGPoint(x: 63, y: 101))
            p.addQuadCurve(to: CGPoint(x: 58, y: 97), control: CGPoint(x: 58, y: 102))
            p.addLine(to: CGPoint(x: 53, y: 72))
            p.addQuadCurve(to: CGPoint(x: 57, y: 66), control: CGPoint(x: 52, y: 67))
            p.closeSubpath()
        }
        stroke(ivory, width: 3.5) { p in
            p.move(to: CGPoint(x: 75, y: 110)); p.addLine(to: CGPoint(x: 101, y: 106))
        }

        ellipse(Self.coral, x: 48, y: 9, width: 20, height: 20)
        fill(Self.coral) { p in
            p.move(to: CGPoint(x: 54, y: 34))
            p.addCurve(to: CGPoint(x: 20, y: 54), control1: CGPoint(x: 36, y: 25), control2: CGPoint(x: 26, y: 35))
            p.addCurve(to: CGPoint(x: 32, y: 81), control1: CGPoint(x: 18, y: 66), control2: CGPoint(x: 26, y: 74))
            p.addQuadCurve(to: CGPoint(x: 27, y: 106), control: CGPoint(x: 37, y: 96))
            p.addCurve(to: CGPoint(x: 40, y: 75), control1: CGPoint(x: 46, y: 100), control2: CGPoint(x: 45, y: 88))
            p.addQuadCurve(to: CGPoint(x: 43, y: 54), control: CGPoint(x: 45, y: 62))
            p.addQuadCurve(to: CGPoint(x: 54, y: 34), control: CGPoint(x: 38, y: 42))
            p.closeSubpath()

            p.move(to: CGPoint(x: 51, y: 35))
            p.addCurve(to: CGPoint(x: 84, y: 55), control1: CGPoint(x: 71, y: 39), control2: CGPoint(x: 79, y: 42))
            p.addLine(to: CGPoint(x: 78, y: 57))
            p.addCurve(to: CGPoint(x: 57, y: 46), control1: CGPoint(x: 73, y: 46), control2: CGPoint(x: 63, y: 47))
            p.closeSubpath()
        }
        stroke(Self.teal, width: 8) { p in
            p.move(to: CGPoint(x: 51, y: 53)); p.addLine(to: CGPoint(x: 82, y: 80))
        }
        fill(Self.teal) { p in
            p.move(to: CGPoint(x: 78, y: 75))
            p.addCurve(to: CGPoint(x: 100, y: 75), control1: CGPoint(x: 82, y: 65), control2: CGPoint(x: 95, y: 67))
            p.addLine(to: CGPoint(x: 91, y: 74))
            p.addLine(to: CGPoint(x: 86, y: 80))
            p.addLine(to: CGPoint(x: 89, y: 88))
            p.addLine(to: CGPoint(x: 99, y: 91))
            p.addCurve(to: CGPoint(x: 78, y: 80), control1: CGPoint(x: 88, y: 98), control2: CGPoint(x: 75, y: 91))
            p.closeSubpath()
        }
        fill(ivory) { p in
            p.move(to: CGPoint(x: 43, y: 36))
            p.addQuadCurve(to: CGPoint(x: 49, y: 56), control: CGPoint(x: 33, y: 52))
            p.addQuadCurve(to: CGPoint(x: 52, y: 65), control: CGPoint(x: 59, y: 60))
            p.addQuadCurve(to: CGPoint(x: 30, y: 45), control: CGPoint(x: 27, y: 60))
            p.addQuadCurve(to: CGPoint(x: 43, y: 36), control: CGPoint(x: 35, y: 39))
            p.closeSubpath()
        }
    }
}
