// Promo images for the README and for posting.
//   swiftc -O tools/promo.swift -o /tmp/promo && /tmp/promo            (run from the repo root)
// Writes into assets/promo/:
//   banner.png     1280×640  social card: icon, name, tagline, the critters
//   critters.png   1280×400  who is who
//   demo.gif        720×300  idle critters get whipped and go back to work (drawn from the sprite data, not a screen recording)
//   shot-1…5.jpg   1440×900  web-sized copies of AppStore/screenshots (run tools/screenshots.sh first)
// Sprites come from desktop/src/shared/sprites.json, the same data both apps draw.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let out = "assets/promo"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a) }
func hex(_ s: String) -> NSColor { hex(Int(s.dropFirst(), radix: 16) ?? 0) }

struct Sprite { let rows: [String]; let body, light, accent, cheek: NSColor }
let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "desktop/src/shared/sprites.json"))) as! [String: Any]
let rawSprites = json["sprites"] as! [String: [String: Any]]
let kinds = json["kinds"] as! [String: String]
let ink = hex(0x2A2433)
func sprite(_ kind: String) -> Sprite {
    let d = rawSprites[kinds[kind]!]!
    return Sprite(rows: d["rows"] as! [String], body: hex(d["body"] as! String), light: hex(d["light"] as! String),
                  accent: hex(d["accent"] as! String), cheek: hex(d["cheek"] as! String))
}
let cast: [(kind: String, name: String, friend: String)] = [
    ("claudeCode", "Claude Code", "crab"), ("codex", "Codex", "axolotl"), ("cursor", "Cursor", "squid"),
    ("gemini", "Gemini CLI", "pufferfish"), ("antigravity", "Antigravity", "whale"), ("other", "anything else", "blob"),
]

/// Draw a sprite with its top-left at (x, y) in a top-left-origin space of the given canvas height.
func draw(_ s: Sprite, x: CGFloat, y: CGFloat, cell: CGFloat, canvasH: CGFloat, dim: CGFloat = 1) {
    for (r, row) in s.rows.enumerated() {
        for (c, ch) in row.enumerated() {
            let col: NSColor?
            switch ch { case "K", "E": col = ink; case "B": col = s.body; case "L": col = s.light; case "A": col = s.accent; case "C": col = s.cheek; default: col = nil }
            guard let color = col else { continue }
            color.withAlphaComponent(dim).setFill()
            NSRect(x: x + CGFloat(c) * cell, y: canvasH - (y + CGFloat(r + 1) * cell), width: cell, height: cell).fill()
        }
    }
}
/// A dark rounded tile like the ones in the app, top-left origin.
func tile(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, canvasH: CGFloat, fill: NSColor = hex(0x1B1E2B), radius: CGFloat = 16) {
    fill.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: canvasH - y - h, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func text(_ s: String, x: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, canvasH: CGFloat, align: NSTextAlignment = .left, rounded: Bool = true) {
    let p = NSMutableParagraphStyle(); p.alignment = align
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
    let h = size * 1.35
    NSString(string: s).draw(in: NSRect(x: x, y: canvasH - y - h, width: w, height: h), withAttributes: attrs)
}
func bitmap(_ w: Int, _ h: Int, _ body: (CGFloat, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    body(CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func save(_ rep: NSBitmapImageRep, _ name: String, jpeg: Bool = false) {
    let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84])! : rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: out + "/" + name))
    print("wrote", name, data.count / 1024, "KB")
}
func orangeBackdrop(_ w: CGFloat, _ h: CGFloat) {
    NSGradient(starting: hex(0xF29572), ending: hex(0xA63E22))!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
    NSGradient(colorsAndLocations: (hex(0xFFFFFF, 0.16), 0), (hex(0xFFFFFF, 0), 0.6))!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
}

// MARK: banner — 1280×640
save(bitmap(1280, 640) { w, h in
    orangeBackdrop(w, h)
    if let icon = NSImage(contentsOfFile: "assets/icon-1024.png") {
        let shadow = NSShadow(); shadow.shadowColor = hex(0x000000, 0.35); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        let r = NSRect(x: 84, y: h - 84 - 190, width: 190, height: 190)
        hex(0xB04426).setFill(); NSBezierPath(roundedRect: r, xRadius: 43, yRadius: 43).fill()        // carries the shadow
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 43, yRadius: 43).addClip()                              // the PNG is a full-bleed square
        icon.draw(in: r)
        NSGraphicsContext.restoreGraphicsState()
    }
    text("Whiplash", x: 310, y: 84, w: 900, size: 104, weight: .heavy, color: .white, canvasH: h)
    text("Whip your AI agents into shape", x: 314, y: 214, w: 900, size: 40, weight: .semibold, color: hex(0xFFFFFF, 0.92), canvasH: h)
    // the cast, on app-style tiles
    let cell: CGFloat = 11, tw: CGFloat = 12 * cell + 44, th: CGFloat = 10 * cell + 44, gap: CGFloat = 16
    let total = CGFloat(cast.count) * tw + CGFloat(cast.count - 1) * gap
    var x = (w - total) / 2
    for c in cast {
        tile(x: x, y: 336, w: tw, h: th, canvasH: h, fill: hex(0xF7F2EC), radius: 22)          // light tiles, like the list view, so the ink outlines show
        draw(sprite(c.kind), x: x + 22, y: 358, cell: cell, canvasH: h)
        text(c.name, x: x - 8, y: 336 + th + 10, w: tw + 16, size: 18, weight: .bold, color: .white, canvasH: h, align: .center)
        x += tw + gap
    }
    text("See who's working, who's waiting for you — as pixel critters on your desktop", x: 0, y: 584, w: w, size: 21, weight: .medium, color: hex(0xFFFFFF, 0.85), canvasH: h, align: .center)
}, "banner.png")

// MARK: critters — 1280×400
save(bitmap(1280, 400) { w, h in
    hex(0x12141D).setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    text("One critter per agent", x: 0, y: 34, w: w, size: 34, weight: .heavy, color: .white, canvasH: h, align: .center)
    let cell: CGFloat = 12, tw: CGFloat = 12 * cell + 44, th: CGFloat = 10 * cell + 44, gap: CGFloat = 18
    let total = CGFloat(cast.count) * tw + CGFloat(cast.count - 1) * gap
    var x = (w - total) / 2
    for c in cast {
        tile(x: x, y: 108, w: tw, h: th, canvasH: h, fill: hex(0xF7F2EC), radius: 22)
        draw(sprite(c.kind), x: x + 22, y: 130, cell: cell, canvasH: h)
        text(c.name, x: x - 8, y: 108 + th + 12, w: tw + 16, size: 19, weight: .bold, color: .white, canvasH: h, align: .center)
        text("the " + c.friend, x: x - 8, y: 108 + th + 40, w: tw + 16, size: 15, weight: .medium, color: hex(0xFFFFFF, 0.55), canvasH: h, align: .center)
        x += tw + gap
    }
}, "critters.png")

// MARK: demo.gif — 720×300, 34 frames
// 0–9 everyone is asleep · 10–15 the whip sweeps across · 16–23 they jump one after another · 24–33 back to work
let gifURL = URL(fileURLWithPath: out + "/demo.gif")
let frames = 34
let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for f in 0..<frames {
    let rep = bitmap(720, 300) { w, h in
        hex(0x12141D).setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        tile(x: 24, y: 70, w: w - 48, h: 170, canvasH: h, fill: hex(0x1B1E2B), radius: 22)
        let cell: CGFloat = 6, tw: CGFloat = 12 * cell + 20, gap: CGFloat = 14
        let total = CGFloat(cast.count) * tw + CGFloat(cast.count - 1) * gap
        let x0 = (w - total) / 2
        let whipX: CGFloat? = (10...15).contains(f) ? x0 - 60 + CGFloat(f - 10) / 5 * (total + 120) : nil
        for (i, c) in cast.enumerated() {
            let x = x0 + CGFloat(i) * (tw + gap)
            let hitFrame = 12 + i                                   // the whip reaches each one a frame apart
            let awake = f >= hitFrame
            var y: CGFloat = 108
            if awake, f - hitFrame < 5 { y -= sin(CGFloat(f - hitFrame) / 4 * .pi) * 22 }      // jump
            else if awake, (f + i) % 4 < 2 { y -= 2 }                                          // working bob
            tile(x: x, y: 96, w: tw, h: 10 * cell + 24, canvasH: h, fill: !awake ? hex(0x6B6F80) : (f - hitFrame < 3 ? hex(0xFFD0C4) : hex(0xF7F2EC)), radius: 12)
            draw(sprite(c.kind), x: x + 10, y: y, cell: cell, canvasH: h, dim: awake ? 1 : 0.75)
            if !awake { text((f / 3 + i) % 2 == 0 ? "z" : "Z", x: x + tw - 20, y: 86, w: 24, size: 15, weight: .bold, color: hex(0xFFFFFF, 0.55), canvasH: h) }
            // CPU bar under each tile
            let barY: CGFloat = 96 + 10 * cell + 34
            hex(0xFFFFFF, 0.12).setFill(); NSRect(x: x + 10, y: h - barY - 5, width: tw - 20, height: 5).fill()
            if awake { hex(0xE07A5F).setFill(); NSRect(x: x + 10, y: h - barY - 5, width: (tw - 20) * min(1, 0.25 + CGFloat((f - hitFrame) % 6) * 0.12), height: 5).fill() }
        }
        if let wx = whipX {                                          // the whip: a dark curved lash with a yellow crack at its tip
            let p = NSBezierPath(); p.lineWidth = 6; p.lineCapStyle = .round
            p.move(to: NSPoint(x: wx - 150, y: h - 60)); p.curve(to: NSPoint(x: wx, y: h - 150), controlPoint1: NSPoint(x: wx - 90, y: h - 30), controlPoint2: NSPoint(x: wx - 30, y: h - 90))
            hex(0x0B0B0F).setStroke(); p.stroke()
            hex(0xFFD23A).setStroke()
            for a in stride(from: 0.0, to: 6.28, by: 1.05) {
                let s = NSBezierPath(); s.lineWidth = 3; s.lineCapStyle = .round
                s.move(to: NSPoint(x: wx + CGFloat(cos(a)) * 10, y: h - 150 + CGFloat(sin(a)) * 10)); s.line(to: NSPoint(x: wx + CGFloat(cos(a)) * 22, y: h - 150 + CGFloat(sin(a)) * 22)); s.stroke()
            }
        }
        let caption: String, color: NSColor
        switch f {
        case 0..<10:  caption = "Six agents, all asleep on the job…"; color = hex(0xFFFFFF, 0.75)
        case 10..<18: caption = "WHACK!"; color = hex(0xFFD23A)
        default:      caption = "…and back to work."; color = hex(0x7EE787)
        }
        text(caption, x: 0, y: 18, w: w, size: (10..<18).contains(f) ? 34 : 24, weight: .heavy, color: color, canvasH: h, align: .center)
        text("Whiplash — whip your AI agents into shape", x: 0, y: 256, w: w, size: 15, weight: .semibold, color: hex(0xFFFFFF, 0.5), canvasH: h, align: .center)
    }
    let delay: Double = f == frames - 1 ? 1.4 : (f < 10 ? 0.16 : 0.09)
    CGImageDestinationAddImage(dest, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
CGImageDestinationFinalize(dest)
print("wrote demo.gif", (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int).flatMap { $0 }.map { $0 / 1024 } ?? 0, "KB")

// MARK: web-sized screenshots
for (i, name) in ["1-roam", "2-list", "3-field", "4-whip", "5-body"].enumerated() {
    guard let img = NSImage(contentsOfFile: "AppStore/screenshots/\(name).png") else { print("skip", name); continue }
    save(bitmap(1440, 900) { w, h in img.draw(in: NSRect(x: 0, y: 0, width: w, height: h)) }, "shot-\(i + 1).jpg", jpeg: true)
}
