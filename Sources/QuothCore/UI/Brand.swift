import SwiftUI

/// Quoth's palette, from the app icon: espresso, amber and cream.
enum Brand {
    static let espressoTop = Color(red: 0x46 / 255, green: 0x32 / 255, blue: 0x1F / 255)
    static let espressoBottom = Color(red: 0x1C / 255, green: 0x14 / 255, blue: 0x0E / 255)
    static let amberTop = Color(red: 0xFF / 255, green: 0xC5 / 255, blue: 0x6A / 255)
    static let amberBottom = Color(red: 0xEE / 255, green: 0x8A / 255, blue: 0x25 / 255)
    static let cream = Color(red: 0xFF / 255, green: 0xF1 / 255, blue: 0xDC / 255)

    static let espresso = LinearGradient(colors: [espressoTop, espressoBottom], startPoint: .top, endPoint: .bottom)
    static let amber = LinearGradient(colors: [amberTop, amberBottom], startPoint: .top, endPoint: .bottom)
}

/// One quotation mark from the app icon: a round head and a tail that
/// curls away from it. Closing (”, a "9") has the head on top and the tail
/// down to the left; opening (“, a "6") is the same turned half round.
/// Drawn as one outline, so it fills cleanly at any size.
struct QuoteMarkShape: Shape {
    var opening = false

    /// The icon's geometry: a head of radius 112 and its tail, in a
    /// 224 × 382 box with y pointing down.
    private static let box = CGSize(width: 224, height: 382)
    private static let outline: CGPath = {
        let head = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 224, height: 224), transform: nil)
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 224, y: 112))
        tail.addCurve(to: CGPoint(x: 42, y: 382), control1: CGPoint(x: 224, y: 252), control2: CGPoint(x: 152, y: 342))
        tail.addCurve(to: CGPoint(x: 92, y: 172), control1: CGPoint(x: 102, y: 302), control2: CGPoint(x: 132, y: 232))
        tail.closeSubpath()
        return head.union(tail)
    }()

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.box.width, rect.height / Self.box.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
        if opening { transform = transform.rotated(by: .pi) }
        transform = transform.translatedBy(x: -Self.box.width / 2, y: -Self.box.height / 2)
        return Path(Self.outline.copy(using: &transform) ?? Self.outline)
    }
}

/// A pair of quotation marks, “ or ”, in amber.
struct QuotePair: View {
    var opening = false

    var body: some View {
        HStack(spacing: 1.5) {
            QuoteMarkShape(opening: opening)
            QuoteMarkShape(opening: opening)
        }
        .foregroundStyle(Brand.amber)
        .accessibilityHidden(true)
    }
}
