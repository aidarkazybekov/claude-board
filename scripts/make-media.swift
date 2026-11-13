// Turns raw demo captures into README/social media: framed screenshots, a captioned MP4 tour
// (English and Russian), a looping GIF and cover images.
//
//   build/ClaudeBoard.app/Contents/MacOS/ClaudeBoard --demo --snapshot build/raw
//   swift scripts/make-media.swift build/raw docs/media build/media
//
// Uses only AppKit, AVFoundation and ImageIO.
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: make-media.swift <raw-dir> <docs-media-dir> <build-media-dir>")
    exit(2)
}
let rawDir = args[1], docsDir = args[2], buildDir = args[3]
for d in [docsDir, buildDir] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }

// MARK: - Drawing helpers

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(rawDir)/\(name).png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("missing \(url.path)")
    }
    return img
}

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let colors = [
        CGColor(red: 0.80, green: 0.42, blue: 0.32, alpha: 1),
        CGColor(red: 0.45, green: 0.25, blue: 0.55, alpha: 1),
        CGColor(red: 0.14, green: 0.15, blue: 0.36, alpha: 1),
    ] as CFArray
    let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
}

/// Draws a screenshot as a rounded window with a soft shadow, fitted into `rect` (and scaled by `zoom`).
func drawWindow(_ ctx: CGContext, _ img: CGImage, in rect: CGRect, zoom: CGFloat = 1, alpha: CGFloat = 1) {
    let aspect = CGFloat(img.width) / CGFloat(img.height)
    var w = rect.width, h = w / aspect
    if h > rect.height { h = rect.height; w = h * aspect }
    w *= zoom; h *= zoom
    let r = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    let radius = w * 0.012
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.012), blur: w * 0.035, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(img, in: r)
    ctx.restoreGState()
    // hairline border
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, weight: NSFont.Weight, centerX: CGFloat, top: CGFloat,
              canvasHeight: CGFloat, maxWidth: CGFloat, alpha: CGFloat = 1, color: NSColor = .white)
{
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: para,
    ]
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.boundingRect(with: NSSize(width: maxWidth, height: 1000), options: [.usesLineFragmentOrigin])
    let rect = NSRect(x: centerX - maxWidth / 2, y: canvasHeight - top - bounds.height, width: maxWidth, height: bounds.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    s.draw(with: rect, options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
}

func savePNG(_ img: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Framed screenshots

func framed(_ name: String, width: Int, padRatio: CGFloat = 0.06) -> CGImage {
    let img = load(name)
    let aspect = CGFloat(img.width) / CGFloat(img.height)
    let pad = CGFloat(width) * padRatio
    let innerW = CGFloat(width) - pad * 2
    let height = Int(innerW / aspect + pad * 2)
    let ctx = context(width, height)
    background(ctx, CGFloat(width), CGFloat(height))
    drawWindow(ctx, img, in: CGRect(x: pad, y: pad, width: innerW, height: CGFloat(height) - pad * 2))
    return ctx.makeImage()!
}

// Shots used by README/GUIDE go to docs; extras (light theme, list, sheets) are for posts only.
for s in ["board", "plan", "needs-you", "project", "worklog", "insights"] { savePNG(framed(s, width: 1800), "\(docsDir)/\(s).png") }
for s in ["list", "plan-light", "board-light"] { savePNG(framed(s, width: 1800), "\(buildDir)/\(s).png") }
savePNG(framed("guide", width: 1400, padRatio: 0.08), "\(buildDir)/guide.png")
savePNG(framed("new-task", width: 900, padRatio: 0.1), "\(buildDir)/new-task.png")
print("framed screenshots → \(docsDir), extras → \(buildDir)")

// MARK: - Slides

struct Slide { let shot: String?; let caption: String }

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
        let s = 300 * k
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.draw(icon, in: CGRect(x: W / 2 - s / 2, y: H * 0.47, width: s, height: s))
        ctx.restoreGState()
    }
    drawText(ctx, title, size: 104 * k, weight: .bold, centerX: W / 2, top: H * 0.55, canvasHeight: H, maxWidth: W * 0.9, alpha: alpha)
    drawText(ctx, subtitle, size: 44 * k, weight: .medium, centerX: W / 2, top: H * 0.55 + 135 * k, canvasHeight: H, maxWidth: W * 0.8,
             alpha: alpha * 0.9)
    if let footer {
        drawText(ctx, footer, size: 34 * k, weight: .regular, centerX: W / 2, top: H * 0.86, canvasHeight: H, maxWidth: W * 0.9,
                 alpha: alpha * 0.8)
    }
    return ctx.makeImage()!
}

/// A captioned screenshot slide. `zoom` drives the slow push-in.
func renderSlide(_ w: Int, _ h: Int, _ slide: Slide, zoom: CGFloat) -> CGImage {
    let ctx = context(w, h)
    background(ctx, CGFloat(w), CGFloat(h))
    let W = CGFloat(w), H = CGFloat(h), k = W / 1920
    drawText(ctx, slide.caption, size: 52 * k, weight: .bold, centerX: W / 2, top: 52 * k, canvasHeight: H, maxWidth: W * 0.9)
    if let shot = slide.shot {
        let area = CGRect(x: 110 * k, y: 50 * k, width: W - 220 * k, height: H - 50 * k - 165 * k)
        drawWindow(ctx, cache[shot]!, in: area, zoom: zoom)
    }
    return ctx.makeImage()!
}

var cache: [String: CGImage] = [:]
for s in ["board", "needs-you", "plan", "project", "worklog", "insights"] { cache[s] = load(s) }

struct Script { let lang: String; let intro: (String, String); let slides: [Slide]; let outro: (String, String, String) }

let scripts = [
    Script(lang: "en",
           intro: ("ClaudeBoard", "A task board for everything you ask Claude Code"),
           slides: [
               Slide(shot: "board", caption: "Every request you give Claude Code becomes a ticket"),
               Slide(shot: "needs-you", caption: "See where Claude is waiting on you"),
               Slide(shot: "plan", caption: "Plan each project's tasks. Claude's sessions link to them"),
               Slide(shot: "project", caption: "Follow Claude's plan while it works"),
               Slide(shot: "worklog", caption: "A worklog of what you asked and what got done"),
               Slide(shot: "insights", caption: "Insights: requests per day, status, your rhythm"),
           ],
           outro: ("Free & open source", "macOS 15+ · runs locally · nothing leaves your Mac", "github.com/aidarkazybekov/claude-board")),
    Script(lang: "ru",
           intro: ("ClaudeBoard", "Доска задач для всего, что вы поручаете Claude Code"),
           slides: [
               Slide(shot: "board", caption: "Каждый запрос к Claude Code — тикет на доске"),
               Slide(shot: "needs-you", caption: "Видно, где Claude ждёт вашего ответа"),
               Slide(shot: "plan", caption: "Свои задачи по каждому проекту, с привязкой к сессиям Claude"),
               Slide(shot: "project", caption: "План Claude в реальном времени"),
               Slide(shot: "worklog", caption: "Ворклог: что просили и что сделано"),
               Slide(shot: "insights", caption: "Аналитика: запросы по дням, статусы, ваш ритм"),
           ],
           outro: ("Бесплатно и open source", "macOS 15+ · работает локально · данные не покидают Mac", "github.com/aidarkazybekov/claude-board")),
]

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

func blend(_ a: CGImage, _ b: CGImage, _ t: CGFloat) -> CGImage {
    let ctx = context(a.width, a.height)
    let r = CGRect(x: 0, y: 0, width: a.width, height: a.height)
    ctx.draw(a, in: r)
    ctx.setAlpha(t)
    ctx.draw(b, in: r)
    return ctx.makeImage()!
}

func makeVideo(_ s: Script, path: String) {
    let W = 1920, H = 1080, fps: Int32 = 30
    try? FileManager.default.removeItem(atPath: path)
    let writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
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
    // intro with fade-in from the plain background
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

// MARK: - Covers

func makeCover(_ s: Script, path: String) {
    let W = 1920, H = 1080
    let ctx = context(W, H)
    background(ctx, CGFloat(W), CGFloat(H))
    let k = CGFloat(W) / 1920
    drawText(ctx, s.intro.0, size: 76 * k, weight: .bold, centerX: CGFloat(W) / 2, top: 40 * k, canvasHeight: CGFloat(H), maxWidth: CGFloat(W) * 0.9)
    drawText(ctx, s.intro.1, size: 36 * k, weight: .medium, centerX: CGFloat(W) / 2, top: 135 * k, canvasHeight: CGFloat(H), maxWidth: CGFloat(W) * 0.9, alpha: 0.9)
    drawWindow(ctx, cache["board"]!, in: CGRect(x: 120 * k, y: 40 * k, width: CGFloat(W) - 240 * k, height: CGFloat(H) - 40 * k - 215 * k))
    savePNG(ctx.makeImage()!, path)
    print("cover → \(path)")
}

makeCover(scripts[0], path: "\(docsDir)/cover.png")
makeCover(scripts[1], path: "\(buildDir)/cover-ru.png")
makeGIF(scripts[0], path: "\(docsDir)/tour.gif")
for s in scripts { makeVideo(s, path: "\(buildDir)/claudeboard-tour-\(s.lang).mp4") }
