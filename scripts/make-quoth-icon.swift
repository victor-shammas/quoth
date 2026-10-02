// Draws Quoth's icon: an amber closing quote on an espresso squircle, in the
// same family as Plainview's ".md" and Gaugeline's gauge. Every size is drawn
// natively, so 16 and 32 px stay crisp. Writes packaging/AppIcon.icns, which
// scripts/build-app.sh copies into the app, and docs/assets/quoth-icon.png
// (1024 px) for the README.
//
//     swift scripts/make-quoth-icon.swift
import AppKit

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Apple's icon shape on its 1024 grid (824 body, 100 margin), approximated
/// by a superellipse, scaled to `s`.
func squircle(size s: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let center = s / 2, radius = s * 412 / 1024, n: CGFloat = 5
    for i in 0..<360 {
        let t = 2 * CGFloat.pi * CGFloat(i) / 360
        let x = center + radius * copysign(pow(abs(cos(t)), 2 / n), cos(t))
        let y = center + radius * copysign(pow(abs(sin(t)), 2 / n), sin(t))
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func verticalGradient(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat], top: CGFloat, bottom: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// The quote as two "9" shapes: a round head and a tail that curls down and
/// to the left. Each piece is its own path so overlaps can't cancel out.
func quotePieces(k: CGFloat) -> [CGPath] {
    var pieces: [CGPath] = []
    for dx: CGFloat in [-150, 150] {
        let c = CGPoint(x: (512 + dx) * k, y: 580 * k)
        let r: CGFloat = 112 * k
        pieces.append(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil))
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: c.x + r, y: c.y))
        tail.addCurve(to: CGPoint(x: c.x - 70 * k, y: c.y - 270 * k),
                      control1: CGPoint(x: c.x + r, y: c.y - 140 * k),
                      control2: CGPoint(x: c.x + 40 * k, y: c.y - 230 * k))
        tail.addCurve(to: CGPoint(x: c.x - 20 * k, y: c.y - 60 * k),
                      control1: CGPoint(x: c.x - 10 * k, y: c.y - 190 * k),
                      control2: CGPoint(x: c.x + 20 * k, y: c.y - 120 * k))
        tail.closeSubpath()
        pieces.append(tail)
    }
    return pieces
}

func makeIcon(pixels: Int) -> CGImage {
    let s = CGFloat(pixels), k = s / 1024
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let shape = squircle(size: s)
    let top = s * 924 / 1024, bottom = s * 100 / 1024

    // Drop shadow, as in Apple's macOS icon template.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: rgb(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x1C140E))
    ctx.fillPath()
    ctx.restoreGState()

    // Espresso background.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    verticalGradient(ctx, [rgb(0x46321F), rgb(0x1C140E)], [0, 1], top: top, bottom: bottom)
    ctx.restoreGState()

    // The quote, with one amber gradient across both marks.
    let pieces = quotePieces(k: k)
    let box = pieces.map(\.boundingBoxOfPath).reduce(CGRect.null) { $0.union($1) }
    for piece in pieces {
        ctx.saveGState()
        ctx.addPath(piece)
        ctx.clip()
        verticalGradient(ctx, [rgb(0xFFC56A), rgb(0xEE8A25)], [0, 1], top: box.maxY, bottom: box.minY)
        ctx.restoreGState()
    }

    // Rim: light along the top edge, a little shade along the bottom.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setLineWidth(12 * k)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    verticalGradient(ctx, [rgb(0xFFFFFF, 0.5), rgb(0xFFFFFF, 0), rgb(0x000000, 0), rgb(0x000000, 0.18)],
                     [0, 0.3, 0.85, 1], top: top, bottom: bottom)
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

guard FileManager.default.fileExists(atPath: "packaging/Info.plist") else {
    fatalError("run from the repository root")
}
let iconset = NSTemporaryDirectory() + "QuothIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try writePNG(makeIcon(pixels: size), to: "\(iconset)/icon_\(size)x\(size).png")
    try writePNG(makeIcon(pixels: size * 2), to: "\(iconset)/icon_\(size)x\(size)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "packaging/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try writePNG(makeIcon(pixels: 1024), to: "docs/assets/quoth-icon.png")
print("wrote packaging/AppIcon.icns and docs/assets/quoth-icon.png")
