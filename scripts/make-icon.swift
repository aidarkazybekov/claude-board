// Renders the ClaudeBoard app icon (a three-column board on a warm gradient) to a 1024px PNG.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Squircle-ish background with macOS icon margins
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
ctx.addPath(bg)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bg)
ctx.clip()
let colors = [
    NSColor(calibratedRed: 0.86, green: 0.47, blue: 0.33, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.62, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.48, alpha: 1).cgColor,
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// Three columns
let colW: CGFloat = 196
let gap: CGFloat = 34
let totalW = colW * 3 + gap * 2
let x0 = (size - totalW) / 2
let top = rect.maxY - 120
let colH: CGFloat = 600
for c in 0..<3 {
    let x = x0 + CGFloat(c) * (colW + gap)
    let col = CGPath(roundedRect: CGRect(x: x, y: top - colH, width: colW, height: colH), cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.addPath(col)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    ctx.fillPath()
    let cards = [3, 2, 1][c]
    for k in 0..<cards {
        let cy = top - 26 - CGFloat(k + 1) * 128 - CGFloat(k) * 14
        let card = CGPath(roundedRect: CGRect(x: x + 20, y: cy, width: colW - 40, height: 128), cornerWidth: 20, cornerHeight: 20, transform: nil)
        ctx.addPath(card)
        ctx.setFillColor(NSColor.white.withAlphaComponent(c == 2 ? 1 : 0.92).cgColor)
        ctx.fillPath()
        // card lines
        ctx.setFillColor(NSColor(calibratedWhite: 0.55, alpha: 0.55).cgColor)
        ctx.fill(CGRect(x: x + 42, y: cy + 78, width: colW - 100, height: 14))
        ctx.fill(CGRect(x: x + 42, y: cy + 46, width: colW - 130, height: 14))
    }
}
// Check mark on the "done" card
let cx = x0 + 2 * (colW + gap) + colW / 2
let cy = top - 26 - 128 / 2
ctx.setStrokeColor(NSColor(calibratedRed: 0.24, green: 0.66, blue: 0.36, alpha: 1).cgColor)
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: cx - 40, y: cy))
ctx.addLine(to: CGPoint(x: cx - 10, y: cy - 28))
ctx.addLine(to: CGPoint(x: cx + 44, y: cy + 30))
ctx.strokePath()

// Sparkle
func star(_ c: CGPoint, _ r: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    ctx.addPath(p)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
}
star(CGPoint(x: x0 + colW + gap + colW / 2, y: rect.minY + 92), 58)

img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
