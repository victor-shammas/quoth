#!/usr/bin/env swift
// Composes the App Store screenshots (2880×1800, RGB, no alpha) from renders
// of Quoth's real UI. Everything inside the pill, the Quote Card and Quoth's
// windows is the app's own UI, rendered by Tests/QuothTests/ScreenshotRenderTests.swift.
// This script draws only the desktop backdrop, the headlines, and a generic
// document window standing in for "the app you're typing in".
//
//   QUOTH_RENDER_DIR=/tmp/quoth-shots swift test -Xswiftc -DAPPSTORE --filter ScreenshotRenderTests
//   swift AppStore/screenshots/compose.swift /tmp/quoth-shots AppStore/screenshots
//
// The look follows Gaugeline's screenshots: warm off-white or espresso
// desktops with an amber glow, and a large headline on the left.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: compose.swift <render-dir> <out-dir>\n".utf8))
    exit(2)
}
let src = URL(fileURLWithPath: args[1], isDirectory: true)
let out = URL(fileURLWithPath: args[2], isDirectory: true)

let W: CGFloat = 2880, H: CGFloat = 1800
/// Points → canvas pixels for what this script draws, matching a "3x" Mac.
let px: CGFloat = 3

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func load(_ name: String) -> NSImage {
    let url = src.appendingPathComponent(name)
    guard let rep = NSImageRep(contentsOf: url) as? NSBitmapImageRep else {
        FileHandle.standardError.write(Data("missing \(url.path)\n".utf8)); exit(1)
    }
    let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    rep.size = image.size
    image.addRepresentation(rep)
    return image
}

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceIn)
        return true
    }
}

enum Look { case light, dark }

/// A canvas with a top-left origin, y down.
final class Canvas {
    let ctx: CGContext
    let dark: Bool

    init(_ look: Look) {
        dark = look == .dark
        ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    }

    /// Warm off-white or espresso, with a soft amber glow behind the UI.
    func backdrop(glowAt glow: CGPoint) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let stops: [NSColor] = dark
            ? [hex(0x46321F), hex(0x2A1E14), hex(0x1C140E)]
            : [hex(0xF7F4EF), hex(0xF4F1EC), hex(0xE9DFD1)]
        let gradient = CGGradient(colorsSpace: space, colors: stops.map(\.cgColor) as CFArray, locations: [0, 0.45, 1])!
        ctx.setFillColor(stops[1].cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.drawLinearGradient(gradient, start: CGPoint(x: W * 0.2, y: 0), end: CGPoint(x: W * 0.8, y: H),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glowColors: [NSColor] = dark
            ? [hex(0xEE8A25, 0.30), hex(0xEE8A25, 0.10), hex(0xEE8A25, 0)]
            : [hex(0xFFC56A, 0.42), hex(0xFFC56A, 0.14), hex(0xFFC56A, 0)]
        let radial = CGGradient(colorsSpace: space, colors: glowColors.map(\.cgColor) as CFArray, locations: [0, 0.5, 1])!
        ctx.drawRadialGradient(radial, startCenter: glow, startRadius: 0, endCenter: glow, endRadius: 1250, options: [])
        let deep: [NSColor] = dark
            ? [hex(0x0E0905, 0.55), hex(0x0E0905, 0)]
            : [hex(0xD9C9B3, 0.45), hex(0xD9C9B3, 0)]
        let corner = CGGradient(colorsSpace: space, colors: deep.map(\.cgColor) as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(corner, startCenter: CGPoint(x: 0, y: H), startRadius: 0,
                               endCenter: CGPoint(x: 0, y: H), endRadius: 1300, options: [])
    }

    var ink: NSColor { dark ? hex(0xFFF1DC) : hex(0x24180F) }
    var subInk: NSColor { dark ? hex(0xD9C4A8) : hex(0x6E5F52) }

    @discardableResult
    func text(_ string: String, at point: CGPoint, width: CGFloat, font: NSFont, color: NSColor,
              lineHeight: CGFloat? = nil, kern: CGFloat = 0) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        if let lineHeight { style.minimumLineHeight = lineHeight; style.maximumLineHeight = lineHeight }
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern,
        ])
        let bounds = attributed.boundingRect(with: NSSize(width: width, height: 2000),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading])
        attributed.draw(with: NSRect(x: point.x, y: point.y, width: width, height: ceil(bounds.height)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height)
    }

    /// Headline and subline on the left. Returns the bottom y.
    @discardableResult
    func headline(_ title: String, _ sub: String, x: CGFloat = 190, y: CGFloat, width: CGFloat = 1080) -> CGFloat {
        var bottom = y + text(title, at: CGPoint(x: x, y: y), width: width,
                              font: .systemFont(ofSize: 132, weight: .bold), color: ink, lineHeight: 142, kern: -2.6)
        bottom += 44
        bottom += text(sub, at: CGPoint(x: x, y: bottom), width: width - 40,
                       font: .systemFont(ofSize: 54, weight: .regular), color: subInk, lineHeight: 74)
        return bottom
    }

    func checklist(_ items: [String], x: CGFloat = 196, y: CGFloat) {
        var top = y
        for item in items {
            let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 46, weight: .semibold))!
            tinted(symbol, dark ? hex(0xFFC56A) : hex(0xD9781F))
                .draw(in: NSRect(x: x, y: top + 8, width: symbol.size.width, height: symbol.size.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            text(item, at: CGPoint(x: x + 76, y: top), width: 1000, font: .systemFont(ofSize: 50, weight: .medium), color: ink)
            top += 86
        }
    }

    func shadow(blur: CGFloat = 90, y: CGFloat = 34, alpha: CGFloat? = nil) {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(alpha ?? (dark ? 0.55 : 0.26))
        s.shadowBlurRadius = blur
        s.shadowOffset = NSSize(width: 0, height: y)
        s.set()
    }

    /// Draws a 2x render scaled by `scale`, with a soft shadow, clipped to
    /// rounded corners when `cornerRadius` is set (window captures).
    @discardableResult
    func ui(_ image: NSImage, at origin: CGPoint, scale: CGFloat, cornerRadius: CGFloat = 0, height: CGFloat? = nil,
            shadow drawsShadow: Bool = true) -> NSRect {
        // `height` crops the render from the top, in render pixels.
        let shown = NSSize(width: image.size.width, height: min(height ?? image.size.height, image.size.height))
        let from = NSRect(x: 0, y: image.size.height - shown.height, width: shown.width, height: shown.height)
        let dest = NSRect(x: origin.x, y: origin.y, width: shown.width * scale, height: shown.height * scale)
        NSGraphicsContext.saveGraphicsState()
        if drawsShadow { shadow() }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSShadow().set()
        if cornerRadius > 0 { NSBezierPath(roundedRect: dest, xRadius: cornerRadius, yRadius: cornerRadius).addClip() }
        image.draw(in: dest, from: from, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ctx.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        if cornerRadius > 0 {
            // The window's hairline edge.
            (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.12)).setStroke()
            let edge = NSBezierPath(roundedRect: dest.insetBy(dx: 0.75, dy: 0.75), xRadius: cornerRadius, yRadius: cornerRadius)
            edge.lineWidth = 1.5
            edge.stroke()
        }
        return dest
    }

    /// A generic document window: the app the user is dictating into.
    /// `lines` are paragraphs; the last one gets the caret when `caret` is set.
    func document(_ frame: NSRect, title: String, heading: String?, lines: [String], caret: Bool, faded: Bool = false) {
        let radius = 13 * px
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shadow(alpha: faded ? 0.12 : nil)
        (dark ? hex(0x262019) : hex(0xFFFEFB)).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.10)).setStroke()
        shape.lineWidth = 1.5
        shape.stroke()

        // Title bar.
        let bar: CGFloat = 38 * px
        (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.07)).setFill()
        NSRect(x: frame.minX, y: frame.minY + bar, width: frame.width, height: 1.5).fill()
        for (i, color) in [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)].enumerated() {
            (faded ? (dark ? hex(0x4A4038) : hex(0xDCD6CE)) : color).setFill()
            NSBezierPath(ovalIn: NSRect(x: frame.minX + (14 + CGFloat(i) * 20) * px, y: frame.minY + 13 * px,
                                        width: 12 * px, height: 12 * px)).fill()
        }
        let titleFont = NSFont.systemFont(ofSize: 13 * px, weight: .semibold)
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        text(title, at: CGPoint(x: frame.midX - titleWidth / 2, y: frame.minY + 10.5 * px), width: titleWidth + 4,
             font: titleFont, color: dark ? hex(0xF6EBDD, 0.75) : hex(0x24180F, 0.7))

        // Body.
        let inset: CGFloat = 32 * px
        let width = frame.width - 2 * inset
        var y = frame.minY + bar + 24 * px
        let body = NSFont.systemFont(ofSize: 15 * px)
        let ink = dark ? hex(0xF6EBDD) : hex(0x24180F)
        if let heading {
            y += text(heading, at: CGPoint(x: frame.minX + inset, y: y), width: width,
                      font: .systemFont(ofSize: 22 * px, weight: .bold), color: ink) + 12 * px
        }
        for (i, line) in lines.enumerated() {
            let isLast = i == lines.count - 1
            let shown = isLast && caret ? line + "\u{200A}" : line
            let height = text(shown, at: CGPoint(x: frame.minX + inset, y: y), width: width, font: body, color: ink,
                              lineHeight: 23 * px)
            if isLast && caret {
                // The caret after the last character.
                let storage = NSTextStorage(string: line, attributes: [.font: body])
                let container = NSTextContainer(size: NSSize(width: width, height: 10000))
                container.lineFragmentPadding = 0
                let layout = NSLayoutManager()
                layout.addTextContainer(container); storage.addLayoutManager(layout)
                let style = NSMutableParagraphStyle(); style.minimumLineHeight = 23 * px; style.maximumLineHeight = 23 * px
                storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
                layout.ensureLayout(for: container)
                let glyph = layout.glyphIndexForCharacter(at: max(0, storage.length - 1))
                let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                (dark ? hex(0xFFB457) : hex(0xB8610F)).setFill()
                NSRect(x: frame.minX + inset + rect.maxX + 2 * px, y: y + rect.minY + 3 * px, width: 2 * px, height: 18 * px).fill()
            }
            y += height + 10 * px
        }
    }

    func write(_ name: String) {
        let image = ctx.makeImage()!
        let url = out.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write \(url.path)") }
        print("wrote \(url.path)")
    }
}

let pillRecording = load("pill-recording.png")
let pillLocked = load("pill-locked.png")
let card = load("card.png")
let dictionary = load("settings-dictionary.png")
let model = load("settings-model.png")
let fix = load("fix.png")

/// Centers the pill under `frame`, as Quoth shows it at the bottom of the screen.
func pill(_ c: Canvas, _ image: NSImage, below frame: NSRect, scale: CGFloat = 2) {
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    // The render has the pill's own shadow.
    c.ui(image, at: CGPoint(x: frame.midX - size.width / 2, y: frame.maxY + 10), scale: scale, shadow: false)
}

// 1. Hold to talk (light)
do {
    let c = Canvas(.light)
    c.backdrop(glowAt: CGPoint(x: 2050, y: 900))
    c.headline("Speak, and it’s\nwritten where\nyou type.",
               "Hold a key, speak, and let go. Your words land at the cursor, in any app.", y: 470)
    let doc = NSRect(x: 1380, y: 250, width: 1310, height: 1060)
    c.document(doc, title: "Thursday", heading: "Thursday", lines: [
        "Send the draft to Maria before Friday, and ask her about the reading list.",
        "Book the train for the conference, and check whether the hotel is near the station.",
    ], caret: true)
    pill(c, pillRecording, below: doc)
    c.write("01-hold-to-talk.png")
}

// 2. Hands-free (dark)
do {
    let c = Canvas(.dark)
    c.backdrop(glowAt: CGPoint(x: 2050, y: 900))
    c.headline("Hands-free\nfor long\nthoughts.",
               "Double-tap the key and keep talking. Text appears at each pause. Say “new paragraph”, “bullet point” or “scratch that” as you go.",
               y: 400)
    let doc = NSRect(x: 1380, y: 250, width: 1310, height: 1060)
    c.document(doc, title: "Planning call", heading: "Planning call", lines: [
        "We agreed to move the launch to the second week of May. Sam will own the timeline, and Priya will check the budget before Friday.",
        "Open questions:",
        "• Do we need a second reviewer?",
        "• Who talks to the printer?",
    ], caret: true)
    pill(c, pillLocked, below: doc)
    c.write("02-hands-free.png")
}

// 3. The Quote Card (light)
do {
    let c = Canvas(.light)
    c.backdrop(glowAt: CGPoint(x: 2050, y: 900))
    c.headline("Read it before\nit goes in.",
               "Talk into the Quote Card, fix anything with the keyboard, then press ⌘↩ and it lands where you were.",
               y: 560)
    c.document(NSRect(x: 1430, y: 200, width: 1260, height: 1340), title: "New Message", heading: nil, lines: [
        "To: Sam",
        "Subject: The draft",
    ], caret: false, faded: true)
    c.ui(card, at: CGPoint(x: 1260, y: 640), scale: 1.42)
    c.write("03-quote-card.png")
}

// 4. Dictionary and Fix Last Dictation (light)
do {
    let c = Canvas(.light)
    c.backdrop(glowAt: CGPoint(x: 2050, y: 900))
    c.headline("Your words,\nspelled\nyour way.",
               "Keep names and jargon in a dictionary. When Quoth gets a word wrong, Fix Last Dictation teaches it in seconds.",
               y: 430)
    // The Settings window down to the end of the word list.
    c.ui(dictionary, at: CGPoint(x: 1560, y: 140), scale: 1.1, cornerRadius: 16 * 1.1 * 2, height: 915)
    c.ui(fix, at: CGPoint(x: 1290, y: 1030), scale: 1.05, cornerRadius: 16 * 1.05 * 2)
    c.write("04-dictionary.png")
}

// 5. Private (dark)
do {
    let c = Canvas(.dark)
    c.backdrop(glowAt: CGPoint(x: 2100, y: 900))
    let bottom = c.headline("On your Mac.\nOnly.",
                            "Speech becomes text on your Mac’s Neural Engine. Nothing is saved, and nothing is sent.",
                            y: 420)
    c.checklist(["No account, no sign-in", "Works offline once a model is in", "No analytics, tracking or ads"], y: bottom + 70)
    c.ui(model, at: CGPoint(x: 1490, y: 330), scale: 1.2, cornerRadius: 16 * 1.2 * 2)
    c.write("05-private.png")
}
