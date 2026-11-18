import AppKit
import SwiftUI

/// The app icon's pit-lane light, as a small monochrome glyph for the menu bar: a capsule with
/// three lamps. When something waits on you, the lower lamp is drawn large and solid, like the
/// coral lamp in the icon.
enum PitLights {
    static func menuBarImage(alert: Bool) -> NSImage {
        let size = NSSize(width: 10, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let capsule = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.25, yRadius: 4.25)
            capsule.lineWidth = 1.5
            capsule.stroke()
            let x = rect.midX
            let lamps: [(y: CGFloat, r: CGFloat)] = alert ? [(12.3, 1.25), (9.0, 1.25), (4.8, 2.2)] : [(11.6, 1.35), (8.0, 1.35), (4.4, 1.35)]
            for lamp in lamps {
                NSBezierPath(ovalIn: NSRect(x: x - lamp.r, y: lamp.y - lamp.r, width: lamp.r * 2, height: lamp.r * 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = alert ? "Pitwall: an agent needs you" : "Pitwall"
        return image
    }
}
