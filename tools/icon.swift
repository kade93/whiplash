// Whiplash 아이콘·이모티콘.  swiftc -O tools/icon.swift -o /tmp/icon && /tmp/icon <출력폴더>
// 앱스토어 아이콘 문법: 단색 그라데이션 배경(클로드 주황) + 심볼 하나(무광 검정 채찍, 입체 음영·그림자) + 끝의 노란 균열.
// 배경은 여백 없이 꽉 채운다 — 둥근 모양은 macOS 가 씌운다.
import AppKit

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a) }
typealias P = (x: Double, y: Double)                     // 0…1, 왼쪽 위 기준
func pt(_ p: P, _ s: CGFloat) -> NSPoint { NSPoint(x: p.x * s, y: (1 - p.y) * s) }

let bgTop = rgb(0xF2, 0x95, 0x72), bgBottom = rgb(0xB0, 0x44, 0x26)        // 클로드 주황 → 진한 주황
let whipLight = rgb(0x55, 0x56, 0x5E), whipDark = rgb(0x0C, 0x0C, 0x10)    // 무광 검정 (위 살짝 밝게)
let sparkColor = rgb(0xFF, 0xC8, 0x3A)

// ── 채찍 모양: 곧은 손잡이(굵게) → 크게 휘어 올라갔다 오른쪽 아래로 가늘어지며 떨어지는 줄
let ctrl: [P] = [(0.22, 0.80), (0.33, 0.64), (0.40, 0.46), (0.44, 0.30), (0.56, 0.20), (0.70, 0.25), (0.76, 0.40), (0.69, 0.54), (0.62, 0.62), (0.66, 0.72), (0.78, 0.80)]
let handlePart = 0.16                                     // 앞 16% 는 손잡이 (굵기 일정)
let widthFn: (Double) -> Double = { t in t < handlePart ? 0.105 : max(0.008, 0.105 * pow(1 - (t - handlePart) / (1 - handlePart), 1.5)) }

func smooth(_ p: [P], _ per: Int = 40) -> [P] {
    var out: [P] = []
    for i in 0..<(p.count - 1) {
        let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
        for k in 0..<per {
            let t = Double(k) / Double(per), t2 = t * t, t3 = t2 * t
            out.append((0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
                        0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)))
        }
    }
    out.append(p.last!)
    return out
}
let pts = smooth(ctrl)

/// 폭이 변하는 띠: 양쪽 가장자리를 이어 하나의 다각형 (시작은 둥글게)
func ribbon(_ pts: [P], width: (Double) -> Double, size: CGFloat) -> NSBezierPath {
    var left: [P] = [], right: [P] = []
    let n = pts.count
    for i in 0..<n {
        let a = pts[max(i - 1, 0)], b = pts[min(i + 1, n - 1)]
        var dx = b.x - a.x, dy = b.y - a.y
        let l = max(hypot(dx, dy), 1e-9); dx /= l; dy /= l
        let w = width(Double(i) / Double(n - 1)) / 2
        left.append((pts[i].x - dy * w, pts[i].y + dx * w))
        right.append((pts[i].x + dy * w, pts[i].y - dx * w))
    }
    let path = NSBezierPath()
    path.move(to: pt(left[0], size))
    for p in left.dropFirst() { path.line(to: pt(p, size)) }
    for p in right.reversed() { path.line(to: pt(p, size)) }
    path.close()
    let w0 = width(0) / 2
    path.appendOval(in: NSRect(x: (pts[0].x - w0) * Double(size), y: (1 - pts[0].y - w0) * Double(size), width: 2 * w0 * Double(size), height: 2 * w0 * Double(size)))
    return path
}

/// 입체 채찍: 그림자 → 몸체 그라데이션(위 밝고 아래 어둡게) → 가장자리 하이라이트 → 손잡이 원통 음영 → 균열
func drawWhip(size: CGFloat) {
    let cg = NSGraphicsContext.current!.cgContext
    let body = ribbon(pts, width: widthFn, size: size)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.025), blur: size * 0.06, color: rgb(0, 0, 0, 0.45).cgColor)
    whipDark.setFill(); body.fill()
    cg.restoreGState()
    cg.saveGState(); body.addClip()
    NSGradient(starting: whipLight, ending: whipDark)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -70)
    let hi = ribbon(pts.map { ($0.x - 0.008, $0.y - 0.012) }, width: { t in widthFn(t) * 0.45 }, size: size)
    cg.saveGState(); hi.addClip()
    NSGradient(starting: rgb(255, 255, 255, 0.28), ending: rgb(255, 255, 255, 0.0))!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)   // 무광: 하이라이트 약하게
    cg.restoreGState()
    let hEnd = Int(Double(pts.count) * 0.34)              // 원통 음영은 손잡이를 지나 서서히 사라진다 (경계선 없이)
    let a = pts[0], b = pts[Int(Double(pts.count) * handlePart)]
    let handle = ribbon(Array(pts[0...hEnd]), width: { t in t < 0.45 ? 0.105 : 0.105 * max(0, 1 - (t - 0.45) / 0.55) }, size: size)
    cg.saveGState(); handle.addClip()
    let ang = atan2(-(b.y - a.y), b.x - a.x) * 180 / .pi + 90
    NSGradient(colorsAndLocations: (rgb(255, 255, 255, 0.0), 0.0), (rgb(255, 255, 255, 0.30), 0.35), (rgb(0, 0, 0, 0.0), 0.6), (rgb(0, 0, 0, 0.35), 1.0))!
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: CGFloat(ang))
    cg.restoreGState()
    cg.restoreGState()
    // 균열: 줄 끝에서 부채꼴로 짧은 선 세 개
    sparkColor.setStroke()
    for angd in [-38.0, 0, 38] {
        let th = atan2(0.69, 0.72) + angd * .pi / 180
        let p = NSBezierPath(); p.lineWidth = 0.022 * size; p.lineCapStyle = .round
        p.move(to: pt((0.81 + cos(th) * 0.045, 0.83 + sin(th) * 0.045), size))
        p.line(to: pt((0.81 + cos(th) * 0.12, 0.83 + sin(th) * 0.12), size))
        p.stroke()
    }
}

func drawBackground(size: CGFloat) {
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
    // 위쪽 은은한 빛 + 아래쪽 살짝 어둡게 (깊이감)
    NSGradient(colorsAndLocations: (rgb(255, 255, 255, 0.14), 0.0), (rgb(255, 255, 255, 0.04), 0.45), (rgb(255, 255, 255, 0), 1.0))!
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)                      // 위쪽 빛: 경계 없는 직선 그라데이션
    NSGradient(starting: rgb(0, 0, 0, 0), ending: rgb(0, 0, 0, 0.22))!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
}

func render(size: CGFloat, background: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSGraphicsContext.current!.cgContext.setShouldAntialias(true)
    if background { drawBackground(size: size) }
    let t = NSAffineTransform()
    t.translateX(by: size / 2, yBy: size / 2); t.scale(by: 0.9); t.translateX(by: -size / 2, yBy: -size / 2)   // 둥근 모서리 안전 영역
    NSGraphicsContext.saveGraphicsState(); t.concat()
    drawWhip(size: size)
    NSGraphicsContext.restoreGraphicsState()
    img.unlockFocus()
    return img
}

func savePNG(_ img: NSImage, _ path: String, px: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.interpolationQuality = .high
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out + "/AppIcon.iconset", withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: out + "/assets", withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    savePNG(render(size: CGFloat(max(px, 64)), background: true), "\(out)/AppIcon.iconset/icon_\(name).png", px: px)   // 작은 건 64 로 그려 줄임 (그림자·음영 유지)
}
savePNG(render(size: 1024, background: true), out + "/assets/icon-1024.png", px: 1024)
savePNG(render(size: 256, background: false), out + "/assets/whiplash-emoji.png", px: 256)
savePNG(render(size: 128, background: false), out + "/assets/whiplash-emoji-128.png", px: 128)
print("done")
