// Turns the demo board's shots into everything published: framed screenshots for the README and
// guide, the site's hero and crops, link-preview cards, a looping GIF and a captioned tour video
// (English and Russian).
//
//   scripts/build-app.sh --no-install
//   build/Pitwall.app/Contents/MacOS/Pitwall --media "$PWD/build/raw"   # off screen, never takes focus
//   swift scripts/make-media.swift build/raw docs build/media
//
// Uses only AppKit, AVFoundation and ImageIO.
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: make-media.swift <raw-dir> <docs-dir> <build-media-dir>")
    exit(2)
}
let rawDir = args[1], docs = args[2], buildDir = args[3]
let mediaDir = "\(docs)/media", siteDir = "\(docs)/site"
for d in [mediaDir, siteDir, buildDir] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }

// MARK: - Images

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(rawDir)/\(name).png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("missing \(url.path)")
    }
    return img
}

/// The shots are rendered at the screen's scale; crops are given in points.
func crop(_ img: CGImage, points: CGFloat, _ r: CGRect) -> CGImage {
    let k = CGFloat(img.width) / points
    return img.cropping(to: CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k))!
}

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

func resized(_ img: CGImage, width: Int) -> CGImage {
    let h = Int((CGFloat(width) * CGFloat(img.height) / CGFloat(img.width)).rounded())
    let ctx = context(width, h)
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: h))
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String, quality: Double = 0.86) {
    let jpeg = path.hasSuffix(".jpg")
    let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type, 1, nil)!
    CGImageDestinationAddImage(dest, img, jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary : nil)
    CGImageDestinationFinalize(dest)
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// The app's ink, with a coral glow from the top left and a blue one from the bottom right.
func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let base = CGGradient(colorsSpace: space, colors: [rgb(0x1B1D24), rgb(0x0E0F14)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
    let r = max(w, h)
    let coral = CGGradient(colorsSpace: space, colors: [rgb(0xFF6A3D, 0.38), rgb(0xFF6A3D, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(coral, startCenter: CGPoint(x: w * 0.08, y: h * 1.02), startRadius: 0,
                           endCenter: CGPoint(x: w * 0.08, y: h * 1.02), endRadius: r * 0.62, options: [])
    let blue = CGGradient(colorsSpace: space, colors: [rgb(0x3D6FE0, 0.30), rgb(0x3D6FE0, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(blue, startCenter: CGPoint(x: w * 0.95, y: -h * 0.05), startRadius: 0,
                           endCenter: CGPoint(x: w * 0.95, y: -h * 0.05), endRadius: r * 0.6, options: [])
}

/// Draws a shot as a rounded window with a soft shadow, fitted into `rect` and scaled by `zoom`.
/// With `bleed`, the window keeps `rect`'s width and its top edge, and runs off the canvas below.
func drawWindow(_ ctx: CGContext, _ img: CGImage, in rect: CGRect, zoom: CGFloat = 1, alpha: CGFloat = 1, bleed: Bool = false) {
    let aspect = CGFloat(img.width) / CGFloat(img.height)
    var w = rect.width, h = w / aspect
    if !bleed && h > rect.height { h = rect.height; w = h * aspect }
    w *= zoom; h *= zoom
    let r = bleed ? CGRect(x: rect.midX - w / 2, y: rect.maxY - h, width: w, height: h)
        : CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    let radius = max(8, w * 0.011)
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.012), blur: w * 0.04, color: CGColor(gray: 0, alpha: 0.6))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xF4F5F9))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(img, in: r)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, weight: NSFont.Weight, centerX: CGFloat, top: CGFloat,
              canvasHeight: CGFloat, maxWidth: CGFloat, alpha: CGFloat = 1, color: NSColor = .white)
{
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: rounded(size, weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: para,
        .kern: weight == .heavy || weight == .bold ? -size * 0.015 : 0,
    ]
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.boundingRect(with: NSSize(width: maxWidth, height: 1000), options: [.usesLineFragmentOrigin])
    let rect = NSRect(x: centerX - maxWidth / 2, y: canvasHeight - top - bounds.height, width: maxWidth, height: bounds.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    s.draw(with: rect, options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Shots

// Point sizes the shots were rendered at (see Marketing.swift).
let standard: CGFloat = 1600, hero: CGFloat = 1760, wide: CGFloat = 2280

var shots: [String: CGImage] = [:]
for s in ["board", "plan", "project", "agent", "worklog", "insights", "list", "board-dark", "plan-dark", "insights-dark"] { shots[s] = load(s) }
let needsWide = load("needs-you")
// The waiting ticket, the Done column and the details panel with the agent's question.
shots["needs-you"] = crop(needsWide, points: wide, CGRect(x: 880, y: 0, width: 1400, height: 1060))

func framed(_ img: CGImage, width: Int, padRatio: CGFloat = 0.055) -> CGImage {
    let aspect = CGFloat(img.width) / CGFloat(img.height)
    let pad = CGFloat(width) * padRatio
    let innerW = CGFloat(width) - pad * 2
    let height = Int(innerW / aspect + pad * 2)
    let ctx = context(width, height)
    background(ctx, CGFloat(width), CGFloat(height))
    drawWindow(ctx, img, in: CGRect(x: pad, y: pad, width: innerW, height: CGFloat(height) - pad * 2))
    return ctx.makeImage()!
}

// README and guide.
for s in ["board", "plan", "needs-you", "project", "worklog", "insights"] { save(framed(shots[s]!, width: 1800), "\(mediaDir)/\(s).png") }
save(framed(load("discovery"), width: 1280, padRatio: 0.07), "\(mediaDir)/discovery.jpg")
let week = load("week-card")
save(resized(week, width: min(1080, week.width)), "\(mediaDir)/week-card.jpg", quality: 0.9)
// Extras for posts.
for s in ["list", "agent", "board-dark", "plan-dark", "insights-dark"] { save(framed(shots[s]!, width: 1800), "\(buildDir)/\(s).png") }
for (s, w) in [("guide", 1400), ("new-task", 900), ("settings", 1100), ("menubar", 700), ("share-sheet", 1300)] {
    save(framed(load(s), width: w, padRatio: 0.08), "\(buildDir)/\(s).png")
}
print("framed screenshots → \(mediaDir), extras → \(buildDir)")

// The site: hero in both themes (no frame, the page styles it) and crops for the feature rows.
save(resized(shots["board"]!, width: 2200), "\(siteDir)/hero-light.jpg", quality: 0.84)
save(resized(shots["board-dark"]!, width: 2200), "\(siteDir)/hero-dark.jpg", quality: 0.84)
let siteCrops: [(String, CGImage, CGFloat, CGRect, Int)] = [
    ("needs-you", needsWide, wide, CGRect(x: 1205, y: 0, width: 1075, height: 889), 1200),
    ("plan", shots["plan"]!, standard, CGRect(x: 252, y: 0, width: 918, height: 556), 1400),
    ("worklog", shots["worklog"]!, standard, CGRect(x: 252, y: 128, width: 918, height: 505), 1200),
    ("insights", shots["insights"]!, standard, CGRect(x: 262, y: 124, width: 1316, height: 639), 1400),
]
for (name, img, points, rect, width) in siteCrops {
    save(resized(crop(img, points: points, rect), width: width), "\(siteDir)/\(name).jpg", quality: 0.85)
}
print("site images → \(siteDir)")

// MARK: - Words

struct Slide { let shot: String; let caption: String }
struct Script { let lang: String; let intro: (String, String); let slides: [Slide]; let outro: (String, String, String) }

let scripts = [
    Script(lang: "en",
           intro: ("Pitwall", "Everything you ask your coding agents, on one board"),
           slides: [
               Slide(shot: "board", caption: "Every request to your coding agents becomes a ticket"),
               Slide(shot: "needs-you", caption: "See which agent is waiting on you, and what it asked"),
               Slide(shot: "plan", caption: "Plan each project's tasks. Agent sessions link to them"),
               Slide(shot: "project", caption: "Follow an agent's plan while it works"),
               Slide(shot: "worklog", caption: "A worklog of what you asked and what got done"),
               Slide(shot: "insights", caption: "Claude Code, Codex, Cursor, Gemini CLI, Antigravity: who did what"),
           ],
           outro: ("Free & open source", "macOS 15+ · runs locally · nothing leaves your Mac", "github.com/aidarkazybekov/pitwall")),
    Script(lang: "ru",
           intro: ("Pitwall", "Всё, что вы поручаете кодинг-агентам, на одной доске"),
           slides: [
               Slide(shot: "board", caption: "Каждый запрос к кодинг-агентам становится тикетом"),
               Slide(shot: "needs-you", caption: "Видно, какой агент ждёт вашего ответа и что он спросил"),
               Slide(shot: "plan", caption: "Свои задачи по каждому проекту, с привязкой к сессиям агентов"),
               Slide(shot: "project", caption: "План агента в реальном времени"),
               Slide(shot: "worklog", caption: "Ворклог: что просили и что сделано"),
               Slide(shot: "insights", caption: "Claude Code, Codex, Cursor, Gemini CLI, Antigravity: кто что сделал"),
           ],
           outro: ("Бесплатно и open source", "macOS 15+ · работает локально · данные не покидают Mac", "github.com/aidarkazybekov/pitwall")),
]

// MARK: - Frames

let icon: CGImage? = {
    let p = "build/icon-1024.png"
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}()

func renderTitle(_ w: Int, _ h: Int, title: String, subtitle: String, footer: String?, alpha: CGFloat = 1) -> CGImage {
    let ctx = context(w, h)
    background(ctx, CGFloat(w), CGFloat(h))
    let W = CGFloat(w), H = CGFloat(h), k = W / 1920
    if let icon {
        let s = 280 * k
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.draw(icon, in: CGRect(x: W / 2 - s / 2, y: H * 0.49, width: s, height: s))
        ctx.restoreGState()
    }
    drawText(ctx, title, size: 104 * k, weight: .heavy, centerX: W / 2, top: H * 0.55, canvasHeight: H, maxWidth: W * 0.9, alpha: alpha)
    drawText(ctx, subtitle, size: 44 * k, weight: .semibold, centerX: W / 2, top: H * 0.55 + 140 * k, canvasHeight: H, maxWidth: W * 0.8,
             alpha: alpha * 0.85)
    if let footer {
        drawText(ctx, footer, size: 32 * k, weight: .medium, centerX: W / 2, top: H * 0.86, canvasHeight: H, maxWidth: W * 0.9,
                 alpha: alpha * 0.7)
    }
    return ctx.makeImage()!
}

/// A captioned shot. `zoom` drives the slow push-in.
func renderSlide(_ w: Int, _ h: Int, _ slide: Slide, zoom: CGFloat) -> CGImage {
    let ctx = context(w, h)
    background(ctx, CGFloat(w), CGFloat(h))
    let W = CGFloat(w), H = CGFloat(h), k = W / 1920
    drawText(ctx, slide.caption, size: 52 * k, weight: .bold, centerX: W / 2, top: 50 * k, canvasHeight: H, maxWidth: W * 0.92)
    let area = CGRect(x: 110 * k, y: 50 * k, width: W - 220 * k, height: H - 50 * k - 165 * k)
    drawWindow(ctx, shots[slide.shot]!, in: area, zoom: zoom)
    return ctx.makeImage()!
}

/// Title on top, the board below running off the bottom edge: covers and link previews.
func renderCard(_ w: Int, _ h: Int, _ s: Script, fitted: Bool) -> CGImage {
    let ctx = context(w, h)
    background(ctx, CGFloat(w), CGFloat(h))
    let W = CGFloat(w), H = CGFloat(h), k = W / 1200
    drawText(ctx, s.intro.0, size: 62 * k, weight: .heavy, centerX: W / 2, top: 34 * k, canvasHeight: H, maxWidth: W * 0.9)
    drawText(ctx, s.intro.1, size: 27 * k, weight: .semibold, centerX: W / 2, top: 112 * k, canvasHeight: H, maxWidth: W * 0.9, alpha: 0.85)
    if fitted {
        drawWindow(ctx, shots["board"]!, in: CGRect(x: 80 * k, y: 30 * k, width: W - 160 * k, height: H - 30 * k - 170 * k))
    } else {
        drawWindow(ctx, shots["board"]!, in: CGRect(x: 90 * k, y: 0, width: W - 180 * k, height: H - 172 * k), bleed: true)
    }
    return ctx.makeImage()!
}

func blend(_ a: CGImage, _ b: CGImage, _ t: CGFloat) -> CGImage {
    let ctx = context(a.width, a.height)
    let r = CGRect(x: 0, y: 0, width: a.width, height: a.height)
    ctx.draw(a, in: r)
    ctx.setAlpha(t)
    ctx.draw(b, in: r)
    return ctx.makeImage()!
}

// MARK: - Video

func pixelBuffer(_ img: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: img.width, height: img.height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    CVPixelBufferUnlockBaseAddress(buf, [])
    return buf
}

func makeVideo(_ s: Script, width W: Int, height H: Int, bitrate: Int, path: String) {
    let fps: Int32 = 30
    try? FileManager.default.removeItem(atPath: path)
    let writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var frame: Int64 = 0
    func emit(_ img: CGImage) {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        adaptor.append(pixelBuffer(img, pool: adaptor.pixelBufferPool!), withPresentationTime: CMTime(value: frame, timescale: fps))
        frame += 1
    }
    let hold = 3.2, fade = 0.5
    let introImg = renderTitle(W, H, title: s.intro.0, subtitle: s.intro.1, footer: nil)
    let outroImg = renderTitle(W, H, title: s.outro.0, subtitle: s.outro.1, footer: s.outro.2)
    let blank = renderTitle(W, H, title: "", subtitle: "", footer: nil, alpha: 0)
    for i in 0..<Int(0.6 * Double(fps)) { emit(blend(blank, introImg, CGFloat(i) / CGFloat(0.6 * Double(fps)))) }
    for _ in 0..<Int(1.8 * Double(fps)) { emit(introImg) }
    var previous = introImg
    for slide in s.slides {
        let frames = Int((hold + fade) * Double(fps))
        for i in 0..<frames {
            let t = CGFloat(i) / CGFloat(frames)
            let img = renderSlide(W, H, slide, zoom: 1 + 0.035 * t)
            let f = Double(i) / Double(fps)
            emit(f < fade ? blend(previous, img, CGFloat(f / fade)) : img)
            if i == frames - 1 { previous = img }
        }
    }
    for i in 0..<Int(fade * Double(fps)) { emit(blend(previous, outroImg, CGFloat(i) / CGFloat(fade * Double(fps)))) }
    for _ in 0..<Int(2.6 * Double(fps)) { emit(outroImg) }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    print("video → \(path) (\(String(format: "%.1f", Double(frame) / Double(fps))) s)")
}

// MARK: - GIF (README)

func makeGIF(_ s: Script, path: String) {
    let W = 1100, H = 619
    var frames: [(CGImage, Double)] = []
    let intro = renderTitle(W, H, title: s.intro.0, subtitle: s.intro.1, footer: nil)
    frames.append((intro, 1.8))
    var prev = intro
    for slide in s.slides {
        let img = renderSlide(W, H, slide, zoom: 1)
        for k in 1...3 { frames.append((blend(prev, img, CGFloat(k) / 4), 0.07)) }
        frames.append((img, 2.6))
        prev = img
    }
    let outro = renderTitle(W, H, title: s.outro.0, subtitle: s.outro.1, footer: s.outro.2)
    for k in 1...3 { frames.append((blend(prev, outro, CGFloat(k) / 4), 0.07)) }
    frames.append((outro, 2.4))
    try? FileManager.default.removeItem(atPath: path)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (img, delay) in frames {
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    print("gif → \(path)")
}

// MARK: - Output

save(renderCard(1920, 1080, scripts[0], fitted: true), "\(mediaDir)/cover.png")
save(renderCard(1920, 1080, scripts[1], fitted: true), "\(buildDir)/cover-ru.png")
save(renderCard(1200, 630, scripts[0], fitted: false), "\(siteDir)/og.png")
save(renderCard(1200, 630, scripts[1], fitted: false), "\(siteDir)/og-ru.png")
for s in scripts {
    let suffix = s.lang == "en" ? "" : "-ru"
    save(renderSlide(1280, 720, s.slides[0], zoom: 1), "\(siteDir)/tour-poster\(suffix).jpg", quality: 0.85)
}
print("covers, link previews and posters done")
makeGIF(scripts[0], path: "\(mediaDir)/tour.gif")
for s in scripts {
    let suffix = s.lang == "en" ? "" : "-ru"
    makeVideo(s, width: 1280, height: 720, bitrate: 1_500_000, path: "\(siteDir)/tour-720\(suffix).mp4")
    makeVideo(s, width: 1920, height: 1080, bitrate: 6_000_000, path: "\(buildDir)/pitwall-tour-\(s.lang).mp4")
}
