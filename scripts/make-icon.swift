// Renders the Super Paste app icon into an .iconset directory: a stack of three ink cards (a full card in front, the
// tops of two more peeking out behind it) on a white squircle — clipboard history, at a glance.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.098
    let body = CGRect(x: inset, y: inset * 1.15, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.28))
    ctx.addPath(squircle); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let field = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF), color(0xEFEFEF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(field, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    // Front card, then the tops of the two cards behind it, each narrower, separated by thin gaps.
    let b = body.width, gap = b * 0.035, strip = b * 0.06
    let front = CGSize(width: b * 0.50, height: b * 0.30)
    let bottom = body.midY - (front.height + 2 * (gap + strip)) / 2
    let cards: [(CGRect, CGFloat)] = [
        (CGRect(x: body.midX - front.width / 2, y: bottom, width: front.width, height: front.height), b * 0.06),
        (CGRect(x: body.midX - b * 0.21, y: bottom + front.height + gap, width: b * 0.42, height: strip), strip / 2),
        (CGRect(x: body.midX - b * 0.17, y: bottom + front.height + 2 * gap + strip, width: b * 0.34, height: strip), strip / 2),
    ]
    for (rect, corner) in cards {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    }
    ctx.setFillColor(color(0x141414)); ctx.fillPath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
