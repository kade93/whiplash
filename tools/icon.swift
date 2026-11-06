// Whiplash 아이콘·이모티콘 그리기.  swiftc -O tools/icon.swift -o /tmp/icon && /tmp/icon <출력폴더>
// 32×32 픽셀 격자: 꽃게(에이전트)가 채찍에 맞는 순간, 노란 「짝!」 불꽃.
import AppKit

let crab = [
    "KK........KK",
    "KAK......KAK",
    "KAAK....KAAK",
    ".KAK....KAK.",
    "..KKKKKKKK..",
    ".KBLBBBBBBK.",
    "KBBEBBBBEBBK",
    "KBCBBKKBBCBK",
    ".KKKKKKKKKK.",
    ".K.K....K.K.",
]
// 맞는 순간: 눈을 질끈 감는다 (E → 가로선은 그릴 때 처리)

let palette: [Character: NSColor] = [
    "K": NSColor(srgbRed: 0x2A/255, green: 0x24/255, blue: 0x33/255, alpha: 1),
    "B": NSColor(srgbRed: 0xE0/255, green: 0x7A/255, blue: 0x5F/255, alpha: 1),
    "L": NSColor(srgbRed: 0xF6/255, green: 0xB9/255, blue: 0xA3/255, alpha: 1),
    "A": NSColor(srgbRed: 0xC4/255, green: 0x55/255, blue: 0x3B/255, alpha: 1),
    "C": NSColor(srgbRed: 0xFF/255, green: 0xD3/255, blue: 0xC4/255, alpha: 1),
    "H": NSColor(srgbRed: 0x8B/255, green: 0x5A/255, blue: 0x2B/255, alpha: 1),   // 채찍 손잡이
    "h": NSColor(srgbRed: 0xC8/255, green: 0x8A/255, blue: 0x4A/255, alpha: 1),   // 손잡이 밝은 면
    "w": NSColor(srgbRed: 0x1C/255, green: 0x16/255, blue: 0x22/255, alpha: 1),   // 채찍 줄
    "Y": NSColor(srgbRed: 0xFF/255, green: 0xD9/255, blue: 0x4A/255, alpha: 1),   // 불꽃
    "y": NSColor(srgbRed: 0xFF/255, green: 0xF4/255, blue: 0xB0/255, alpha: 1),
    "S": NSColor(srgbRed: 0x6C/255, green: 0xB8/255, blue: 0xF0/255, alpha: 1),   // 땀
]

var grid = Array(repeating: Array(repeating: Character("."), count: 32), count: 32)
func put(_ x: Int, _ y: Int, _ c: Character) { if x >= 0, x < 32, y >= 0, y < 32 { grid[y][x] = c } }

// 꽃게: 왼쪽 아래
let cx = 5, cy = 19
for (y, row) in crab.enumerated() { for (x, ch) in row.enumerated() where ch != "." { put(cx + x, cy + y, ch) } }
// 채찍 손잡이: 오른쪽 위, 비스듬히
for (i, p) in [(27, 2), (26, 3), (25, 4), (24, 5), (23, 6)].enumerated() {
    put(p.0, p.1, "H"); put(p.0 + 1, p.1, i == 0 ? "H" : "h"); put(p.0, p.1 + 1, "H")
}
// 채찍 줄: 손잡이에서 휘어져 꽃게 머리로
let lash = [(22, 8), (21, 9), (20, 9), (19, 10), (18, 10), (17, 11), (16, 12), (16, 13), (15, 14), (15, 15), (14, 16), (14, 17)]
for p in lash { put(p.0, p.1, "w") }
// 짝! 불꽃: 줄 끝
let star: [(Int, Int, Character)] = [
    (13, 15, "Y"), (12, 14, "y"), (11, 13, "Y"),
    (15, 17, "Y"), (16, 18, "y"),
    (12, 17, "Y"), (11, 18, "y"), (10, 19, "Y"),
    (16, 14, "Y"), (17, 13, "y"), (18, 12, "Y"),
    (13, 17, "y"), (14, 15, "y"), (13, 16, "Y"), (15, 16, "Y"),
    (9, 16, "Y"), (19, 16, "Y"), (14, 12, "Y"), (14, 20, "Y"),
]
for (x, y, c) in star { put(x, y, c) }
// 땀 두 방울
put(17, 21, "S"); put(17, 22, "S"); put(3, 22, "S"); put(3, 23, "S")

func render(size: CGFloat, background: Bool, scale: CGFloat = 1) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(false)
    if background {
        // 맥 아이콘 모양: 둥근 네모 (22%), 깊은 바다색 + 살짝 밝은 위쪽
        let r = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.04, dy: size * 0.04)
        let path = NSBezierPath(roundedRect: r, xRadius: size * 0.21, yRadius: size * 0.21)
        let g = NSGradient(starting: NSColor(srgbRed: 0x2B/255, green: 0x8C/255, blue: 0x96/255, alpha: 1),
                           ending:   NSColor(srgbRed: 0x15/255, green: 0x55/255, blue: 0x5E/255, alpha: 1))!
        g.draw(in: path, angle: -90)
        // 물결 두 줄
        NSColor.white.withAlphaComponent(0.10).setFill()
        let cell = size / 32
        for (y, xs) in [(27, [2, 3, 4, 8, 9, 10, 14, 15, 16, 20, 21, 22, 26, 27, 28]), (30, [5, 6, 7, 11, 12, 13, 17, 18, 19, 23, 24, 25])] {
            for x in xs { NSBezierPath(rect: NSRect(x: CGFloat(x) * cell, y: size - CGFloat(y + 1) * cell, width: cell, height: cell)).fill() }
        }
    }
    let cell = size / 32
    for y in 0..<32 {
        for x in 0..<32 {
            let ch = grid[y][x]
            guard let color = palette[ch == "E" ? "K" : ch] else { continue }
            var rect = NSRect(x: CGFloat(x) * cell, y: size - CGFloat(y + 1) * cell, width: cell, height: cell)
            if ch == "E" { rect.size.height = cell * 0.4 }       // 질끈 감은 눈
            color.setFill()
            NSBezierPath(rect: rect).fill()
        }
    }
    img.unlockFocus()
    return img
}

func savePNG(_ img: NSImage, _ path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width), pixelsHigh: Int(img.size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.interpolationQuality = .none
    img.draw(in: NSRect(origin: .zero, size: img.size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out + "/AppIcon.iconset", withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    savePNG(render(size: CGFloat(px), background: true), "\(out)/AppIcon.iconset/icon_\(name).png")
}
savePNG(render(size: 1024, background: true), out + "/assets/icon-1024.png")
savePNG(render(size: 256, background: false), out + "/assets/whiplash-emoji.png")     // 투명 배경 이모티콘
savePNG(render(size: 128, background: false), out + "/assets/whiplash-emoji-128.png")
print("done")
