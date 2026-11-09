// App Store screenshots (2880×1800) from the app's own snapshot PNGs.
//   swiftc -O tools/shots.swift -o /tmp/shots && /tmp/shots <snapshot folder> <output folder>
// Snapshot folder (from WHIPLASH_SNAPSHOT runs): list.png, field-field.png, roam-critter.png, roam-prompt.png
import AppKit

let W: CGFloat = 2880, H: CGFloat = 1800
let args = CommandLine.arguments
let inDir = args.count > 1 ? args[1] : "."
let outDir = args.count > 2 ? args[2] : "AppStore/screenshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a) }
func load(_ name: String) -> NSImage? { NSImage(contentsOfFile: inDir + "/" + name) }

/// desktop-like backdrop: orange → deep orange gradient, soft top light, faint dock bar
func backdrop() {
    NSGradient(starting: rgb(0xF2, 0x95, 0x72), ending: rgb(0x8E, 0x33, 0x1C))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    NSGradient(colorsAndLocations: (rgb(255, 255, 255, 0.14), 0), (rgb(255, 255, 255, 0), 1))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    // menu bar
    rgb(0, 0, 0, 0.25).setFill(); NSBezierPath(rect: NSRect(x: 0, y: H - 48, width: W, height: 48)).fill()
}

func caption(_ title: String, _ sub: String, y: CGFloat) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let shadow = NSShadow(); shadow.shadowColor = rgb(0, 0, 0, 0.35); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -6)
    let t: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 96, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para, .shadow: shadow]
    let s: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .medium), .foregroundColor: rgb(255, 255, 255, 0.9), .paragraphStyle: para, .shadow: shadow]
    NSString(string: title).draw(in: NSRect(x: 160, y: y, width: W - 320, height: 130), withAttributes: t)
    NSString(string: sub).draw(in: NSRect(x: 160, y: y - 70, width: W - 320, height: 64), withAttributes: s)
}

/// draw an image scaled by factor with a soft shadow, bottom-left at (x, y)
func place(_ img: NSImage, x: CGFloat, y: CGFloat, scale: CGFloat, shadow: Bool = true) {
    let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
    let cg = NSGraphicsContext.current!.cgContext
    cg.saveGState()
    if shadow { cg.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: rgb(0, 0, 0, 0.45).cgColor) }
    img.draw(in: NSRect(origin: NSPoint(x: x, y: y), size: size))
    cg.restoreGState()
}

/// Exactly W×H pixels (lockFocus on a Retina Mac would give 2× and App Store Connect rejects 5760×3600).
func shot(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    backdrop()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir + "/" + name))
    print("wrote", name)
}

let list = load("list.png"), field = load("field-field.png"), critter = load("roam-critter.png"), prompt = load("roam-prompt.png")
let critters: [NSImage] = (1...8).compactMap { load("roam-critter\($0).png") }

// 1. Roaming critters across the desktop
shot("1-roam.png") {
    caption("Your AI agents, as critters", "Each Claude Code, Codex, Cursor or Gemini session walks around your desktop", y: 1420)
    let pool = critters.isEmpty ? [critter].compactMap { $0 } : critters
    let s: CGFloat = 2.6
    for (i, p) in [(300, 760), (820, 620), (1340, 840), (1880, 640), (2340, 780), (620, 1000), (1600, 1060)].enumerated() where i < pool.count {
        place(pool[i], x: CGFloat(p.0), y: CGFloat(p.1), scale: s)
    }
    if let p = prompt { place(p, x: 1180, y: 260, scale: 2.2) }
}

// 2. The list window
shot("2-list.png") {
    caption("Who's working, who's waiting for you", "CPU, memory, cost and the remaining Claude quota as carrots", y: 1560)
    if let l = list {
        let scale = min(1330 / l.size.height, 1200 / l.size.width)
        place(l, x: (W - l.size.width * scale) / 2, y: 80, scale: scale)
    }
}

// 3. Carrot field
shot("3-field.png") {
    caption("Plant them in the carrot field", "One critter per carrot. Carrots vanish as your quota burns — then they strike", y: 1480)
    if let f = field {
        let scale = min(1900 / f.size.width, 1100 / f.size.height)
        place(f, x: (W - f.size.width * scale) / 2, y: 180, scale: scale)
    }
}

// 4. Whip and treat
shot("4-whip.png") {
    caption("Crack the whip. Or give a treat.", "Swipe fast over an idle critter to nudge it back to work; stroke slowly to praise it", y: 1480)
    let pool4 = critters.isEmpty ? [critter, critter].compactMap { $0 } : critters
    if pool4.count >= 2 {
        place(pool4[0], x: 700, y: 560, scale: 4.2)
        place(pool4[1], x: 1700, y: 560, scale: 4.2)
    }
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 150, weight: .black), .foregroundColor: rgb(0xFF, 0xD2, 0x3A), .paragraphStyle: para]
    let big2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 150, weight: .black), .foregroundColor: rgb(0x7E, 0xE7, 0x87), .paragraphStyle: para]
    NSString(string: "Whack!").draw(in: NSRect(x: 560, y: 1050, width: 700, height: 200), withAttributes: big)
    NSString(string: "Yum! 🥕").draw(in: NSRect(x: 1560, y: 1050, width: 700, height: 200), withAttributes: big2)
}

// 5. Body whips
shot("5-body.png") {
    caption("Whip with your body", "AirPods head flick · camera hand swing · say \"whoosh-crack!\" · iPhone & Apple Watch remote", y: 1480)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let f: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 260), .paragraphStyle: para]
    for (i, e) in ["🎧", "📷", "🎤", "⌚️"].enumerated() {
        NSString(string: e).draw(in: NSRect(x: 240 + CGFloat(i) * 620, y: 620, width: 500, height: 320), withAttributes: f)
    }
    let s: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: para]
    for (i, e) in ["Head flick", "Hand swing", "Whoosh-crack!", "Wrist snap"].enumerated() {
        NSString(string: e).draw(in: NSRect(x: 240 + CGFloat(i) * 620, y: 520, width: 500, height: 70), withAttributes: s)
    }
}
