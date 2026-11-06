import SwiftUI

extension ToolDrawing {
    /// Startup Manager: teal figure with coral shirt, yellow/blue power switch at right.
    func startupManager() {
        standingFigure(limbs: Self.teal, shirt: Self.coral)

        // Power-switch housing: yellow body, blue accent strip.
        box(Self.yellow, x: 72, y: 42, width: 44, height: 56, radius: 6)
        box(Self.blue, x: 72, y: 42, width: 44, height: 10, radius: 0)

        // Blue rounded inset behind the glyph.
        box(Self.blue, x: 80, y: 58, width: 28, height: 28, radius: 14)

        // Power glyph: white open arc + vertical line.
        stroke(.white, width: 4) { p in
            let cx: CGFloat = 94
            let cy: CGFloat = 72
            let r: CGFloat = 9
            p.addArc(center: CGPoint(x: cx, y: cy),
                     radius: r,
                     startAngle: .degrees(-45),
                     endAngle: .degrees(225),
                     clockwise: false)
            // Vertical line through the center.
            p.move(to: CGPoint(x: cx, y: cy - 12))
            p.addLine(to: CGPoint(x: cx, y: cy - 2))
        }
    }

    /// Session Recovery: blue figure with yellow shirt, coral/teal browser window with tabs and restore arrow.
    func sessionRecovery() {
        standingFigure(limbs: Self.blue, shirt: Self.yellow)

        // Browser window frame: coral border.
        box(Self.coral, x: 68, y: 34, width: 52, height: 52, radius: 5)

        // Browser interior: white fill.
        box(.white, x: 71, y: 37, width: 46, height: 46, radius: 3)

        // Teal title bar.
        box(Self.teal, x: 71, y: 37, width: 46, height: 10, radius: 0)

        // Three bold tab dots in the title bar.
        ellipse(Self.coral, x: 76, y: 40, width: 4, height: 4)
        ellipse(Self.yellow, x: 84, y: 40, width: 4, height: 4)
        ellipse(Self.lime, x: 92, y: 40, width: 4, height: 4)

        stroke(Self.teal, width: 4) { p in
            let cx: CGFloat = 94
            let cy: CGFloat = 66
            let r: CGFloat = 11
            // Arc from top, sweeping counter-clockwise almost full circle.
            p.addArc(center: CGPoint(x: cx, y: cy),
                     radius: r,
                     startAngle: .degrees(-45),
                     endAngle: .degrees(225),
                     clockwise: false)
            // Arrowhead at the end of the arc (pointing toward the arc's end).
            let endAngle: CGFloat = .pi * 1.25
            let ex = cx + r * cos(endAngle)
            let ey = cy + r * sin(endAngle)
            // Arrowhead lines.
            p.move(to: CGPoint(x: ex - 6, y: ey - 3))
            p.addLine(to: CGPoint(x: ex, y: ey))
            p.addLine(to: CGPoint(x: ex - 3, y: ey + 5))
        }
    }

    /// Software Updates: coral figure with teal shirt, blue download tray with yellow arrow and lime doc.
    func softwareUpdates() {
        standingFigure(limbs: Self.coral, shirt: Self.teal)

        stroke(Self.blue, width: 6) { p in
            p.move(to: CGPoint(x: 70, y: 78))
            p.addLine(to: CGPoint(x: 66, y: 106))
            p.addLine(to: CGPoint(x: 120, y: 106))
            p.addLine(to: CGPoint(x: 116, y: 78))
        }

        // Bold yellow downward arrow above the tray.
        fill(Self.yellow) { p in
            // Shaft.
            p.move(to: CGPoint(x: 83, y: 38))
            p.addLine(to: CGPoint(x: 93, y: 38))
            p.addLine(to: CGPoint(x: 93, y: 62))
            p.addLine(to: CGPoint(x: 100, y: 62))
            p.addLine(to: CGPoint(x: 88, y: 74))
            p.addLine(to: CGPoint(x: 76, y: 62))
            p.addLine(to: CGPoint(x: 83, y: 62))
            p.addLine(to: CGPoint(x: 83, y: 38))
            p.closeSubpath()
        }

        // Small lime document inside the tray (uncluttered, bottom-left area).
        document(Self.lime, x: 96, y: 83, size: 14)
    }
}
