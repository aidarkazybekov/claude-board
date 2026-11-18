// Renders the Pitwall app icon to a 1024px PNG: a pit-lane light on an ink squircle. Three lights
// glow calmly (agents at work); one is coral, like "Needs you": an agent calling you in.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024
let S = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat)], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { rgb($0.0, $0.1) } as CFArray, locations: locations)!
}
/// A continuous-corner rounded rect, close to the macOS icon shape.
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.28  // how far the curve reaches along each edge, relative to the radius
    let e = radius * k
    p.move(to: CGPoint(x: r.minX + e, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - e, y: r.maxY))
    p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY - e), control1: CGPoint(x: r.maxX - e * 0.32, y: r.maxY), control2: CGPoint(x: r.maxX, y: r.maxY - e * 0.32))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + e))
    p.addCurve(to: CGPoint(x: r.maxX - e, y: r.minY), control1: CGPoint(x: r.maxX, y: r.minY + e * 0.32), control2: CGPoint(x: r.maxX - e * 0.32, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX + e, y: r.minY))
    p.addCurve(to: CGPoint(x: r.minX, y: r.minY + e), control1: CGPoint(x: r.minX + e * 0.32, y: r.minY), control2: CGPoint(x: r.minX, y: r.minY + e * 0.32))
    p.addLine(to: CGPoint(x: r.minX, y: r.maxY - e))
    p.addCurve(to: CGPoint(x: r.minX + e, y: r.maxY), control1: CGPoint(x: r.minX, y: r.maxY - e * 0.32), control2: CGPoint(x: r.minX + e * 0.32, y: r.maxY))
    p.closeSubpath()
    return p
}

// The body: macOS icon grid (824pt body inside 1024, 100pt margin), with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: S - 200, height: S - 200)
let shape = squircle(body, 150)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.32))
ctx.addPath(shape)
ctx.setFillColor(rgb(0x14161F))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
// Ink, a little lighter at the top, with a faint coral warmth rising from below.
ctx.drawLinearGradient(gradient([(0x262A38, 1), (0x14161F, 1), (0x0E0F15, 1)], [0, 0.55, 1]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
ctx.drawRadialGradient(gradient([(0xFF6A3D, 0.13), (0xFF6A3D, 0)], [0, 1]),
                       startCenter: CGPoint(x: S / 2, y: 440), startRadius: 0, endCenter: CGPoint(x: S / 2, y: 440), endRadius: 380, options: [])
ctx.restoreGState()
// A hairline of light along the top edge.
ctx.saveGState()
ctx.addPath(squircle(body.insetBy(dx: 2, dy: 2), 148))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

// The light housing: a recessed capsule.
let housing = CGRect(x: S / 2 - 124, y: 186, width: 248, height: 652)
let capsule = CGPath(roundedRect: housing, cornerWidth: 124, cornerHeight: 124, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.55))
ctx.addPath(capsule)
ctx.setFillColor(rgb(0x1D2029))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(capsule)
ctx.clip()
ctx.drawLinearGradient(gradient([(0x2B2F3C, 1), (0x1A1C24, 1)], [0, 1]),
                       start: CGPoint(x: 0, y: housing.maxY), end: CGPoint(x: 0, y: housing.minY), options: [])
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: housing.insetBy(dx: 2, dy: 2), cornerWidth: 122, cornerHeight: 122, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

/// One lamp: a dark socket, a lit lens with a hot centre, and a small specular highlight.
func lamp(y: CGFloat, color: UInt32, hot: UInt32, radius: CGFloat, bright: Bool) {
    let c = CGPoint(x: S / 2, y: y)
    // Socket
    let socket = radius + 10
    ctx.addEllipse(in: CGRect(x: c.x - socket, y: c.y - socket, width: socket * 2, height: socket * 2))
    ctx.setFillColor(rgb(0x101117))
    ctx.fillPath()
    // Glow around a bright lamp
    if bright {
        ctx.drawRadialGradient(gradient([(color, 0.50), (color, 0.14), (color, 0)], [0, 0.45, 1]),
                               startCenter: c, startRadius: radius * 0.7, endCenter: c, endRadius: radius * 2.4, options: [])
    }
    // Lens
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    let alpha: CGFloat = bright ? 1 : 0.5
    ctx.drawRadialGradient(gradient([(hot, alpha), (color, alpha), (color, alpha * 0.75)], [0, 0.55, 1]),
                           startCenter: CGPoint(x: c.x, y: c.y + radius * 0.15), startRadius: 0, endCenter: c, endRadius: radius, options: [])
    ctx.restoreGState()
    // A soft reflection across the top of the lens
    ctx.saveGState()
    let shine = CGRect(x: c.x - radius * 0.62, y: c.y + radius * 0.18, width: radius * 1.24, height: radius * 0.7)
    ctx.addEllipse(in: shine)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, bright ? 0.38 : 0.16), (0xFFFFFF, 0)], [0, 1]),
                           start: CGPoint(x: 0, y: shine.maxY), end: CGPoint(x: 0, y: shine.minY), options: [])
    ctx.restoreGState()
}

// Top to bottom: two agents at work, one calling you in, one more in progress.
lamp(y: 742, color: 0x1FA37A, hot: 0x6FE3B8, radius: 54, bright: false)
lamp(y: 598, color: 0x1FA37A, hot: 0x6FE3B8, radius: 54, bright: false)
lamp(y: 440, color: 0xFF6A3D, hot: 0xFFC2A6, radius: 68, bright: true)
lamp(y: 284, color: 0x3D6FE0, hot: 0x9DB8F5, radius: 54, bright: false)

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
