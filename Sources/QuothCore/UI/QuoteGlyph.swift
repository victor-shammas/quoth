import AppKit

/// Quoth's menu-bar glyph: the closing quote from the app icon, as an
/// 18 × 18 pt template image. Drawn in code, so the binary needs no image
/// resources. Each dictation state has its own look, all template-safe:
/// idle is an outline, recording is filled, locked adds a bar beneath, and
/// transcribing is filled at half strength.
enum QuoteGlyph {
    enum Style: Equatable {
        case idle
        case recording
        case locked
        case transcribing
    }

    static let size = NSSize(width: 18, height: 18)

    static func image(_ style: Style) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            let marks = NSBezierPath()
            marks.append(mark(offsetX: 0))
            marks.append(mark(offsetX: 7.5))
            switch style {
            case .idle:
                NSColor.black.setStroke()
                marks.lineWidth = 1.3
                marks.lineJoinStyle = .round
                marks.stroke()
            case .recording:
                NSColor.black.setFill()
                marks.fill()
            case .locked:
                NSColor.black.setFill()
                marks.fill()
                NSBezierPath(roundedRect: NSRect(x: 3, y: 16.4, width: 12, height: 1.25), xRadius: 0.6, yRadius: 0.6).fill()
            case .transcribing:
                NSColor.black.withAlphaComponent(0.5).setFill()
                marks.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Quoth"
        return image
    }

    /// One "9": a round head (radius 3.25) and a tail curling down and to
    /// the left, as one closed outline so it can be stroked as well as
    /// filled. Coordinates have y pointing down.
    private static func mark(offsetX dx: CGFloat) -> NSBezierPath {
        let center = NSPoint(x: 5.25 + dx, y: 7.0)
        let radius: CGFloat = 3.25
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + radius, y: center.y))
        path.curve(to: NSPoint(x: 3.0 + dx, y: 15.0),
                   controlPoint1: NSPoint(x: 8.5 + dx, y: 11.0),
                   controlPoint2: NSPoint(x: 6.4 + dx, y: 13.6))
        path.curve(to: NSPoint(x: center.x, y: center.y + radius),
                   controlPoint1: NSPoint(x: 4.6 + dx, y: 13.3),
                   controlPoint2: NSPoint(x: 5.3 + dx, y: 11.8))
        // Back round the head: bottom, left, top, right.
        let steps = 36
        for step in 1...steps {
            let angle = (90 + 270 * CGFloat(step) / CGFloat(steps)) * .pi / 180
            path.line(to: NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        path.close()
        return path
    }
}
