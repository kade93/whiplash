import AppKit
import SwiftUI

// MARK: - 앱 아이콘의 채찍 (벡터) — 커서 옆 채찍·커서 이미지용
// tools/icon.swift 와 같은 모양: 곧은 손잡이 → 크게 휘어 올라갔다 오른쪽 아래로 가늘어지는 줄, 끝에 노란 균열.
// 어느 배경 위에서도 보이게 가는 흰 테두리와 그림자를 두른다.

enum WhipArt {
    typealias P = (x: Double, y: Double)
    static let ctrl: [P] = [(0.22, 0.80), (0.33, 0.64), (0.40, 0.46), (0.44, 0.30), (0.56, 0.20), (0.70, 0.25), (0.76, 0.40), (0.69, 0.54), (0.62, 0.62), (0.66, 0.72), (0.78, 0.80)]
    static let handlePart = 0.16
    static func width(_ t: Double) -> Double { t < handlePart ? 0.105 : max(0.012, 0.105 * pow(1 - (t - handlePart) / (1 - handlePart), 1.5)) }

    static let pts: [P] = {
        var out: [P] = []
        let p = ctrl, per = 24
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
    }()

    private static func pt(_ p: P, _ s: CGFloat) -> NSPoint { NSPoint(x: p.x * s, y: (1 - p.y) * s) }

    static func ribbon(size s: CGFloat, extra: Double = 0) -> NSBezierPath {
        var left: [P] = [], right: [P] = []
        let n = pts.count
        for i in 0..<n {
            let a = pts[max(i - 1, 0)], b = pts[min(i + 1, n - 1)]
            var dx = b.x - a.x, dy = b.y - a.y
            let l = max(hypot(dx, dy), 1e-9); dx /= l; dy /= l
            let w = width(Double(i) / Double(n - 1)) / 2 + extra
            left.append((pts[i].x - dy * w, pts[i].y + dx * w)); right.append((pts[i].x + dy * w, pts[i].y - dx * w))
        }
        let path = NSBezierPath()
        path.move(to: pt(left[0], s)); for p in left.dropFirst() { path.line(to: pt(p, s)) }
        for p in right.reversed() { path.line(to: pt(p, s)) }
        path.close()
        let w0 = width(0) / 2 + extra
        path.appendOval(in: NSRect(x: (pts[0].x - w0) * Double(s), y: (1 - pts[0].y - w0) * Double(s), width: 2 * w0 * Double(s), height: 2 * w0 * Double(s)))
        return path
    }

    /// 투명 배경 위 채찍. size = 한 변(px). 흰 테두리 + 그림자 + 검정 몸체 + 균열.
    static func image(size: CGFloat, spark: Bool = true) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let cg = NSGraphicsContext.current!.cgContext
        cg.setShouldAntialias(true)
        let outline = ribbon(size: size, extra: 0.03)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.06, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        NSColor.white.withAlphaComponent(0.95).setFill(); outline.fill()
        cg.restoreGState()
        let body = ribbon(size: size)
        cg.saveGState(); body.addClip()
        NSGradient(starting: NSColor(srgbRed: 0x55/255, green: 0x56/255, blue: 0x5E/255, alpha: 1),
                   ending: NSColor(srgbRed: 0x0C/255, green: 0x0C/255, blue: 0x10/255, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -70)
        cg.restoreGState()
        if spark {
            NSColor(srgbRed: 1, green: 0xC8/255, blue: 0x3A/255, alpha: 1).setStroke()
            for angd in [-38.0, 0, 38] {
                let th = atan2(0.69, 0.72) + angd * .pi / 180
                let p = NSBezierPath(); p.lineWidth = 0.03 * size; p.lineCapStyle = .round
                p.move(to: pt((0.81 + cos(th) * 0.05, 0.83 + sin(th) * 0.05), size))
                p.line(to: pt((0.81 + cos(th) * 0.13, 0.83 + sin(th) * 0.13), size))
                p.stroke()
            }
        }
        img.unlockFocus()
        return img
    }

    /// 메뉴 막대용 템플릿 이미지: 채찍 실루엣 + 균열, 검정 단색 (막대 밝기에 맞춰 시스템이 색을 바꾼다)
    static func templateImage(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSGraphicsContext.current!.cgContext.setShouldAntialias(true)
        NSColor.black.setFill()
        ribbon(size: size, extra: 0.012).fill()                       // 작게 그릴 때 줄 끝이 끊기지 않게 살짝 굵게
        NSColor.black.setStroke()
        for angd in [-38.0, 0, 38] {
            let th = atan2(0.69, 0.72) + angd * .pi / 180
            let p = NSBezierPath(); p.lineWidth = 0.05 * size; p.lineCapStyle = .round
            p.move(to: pt((0.81 + cos(th) * 0.05, 0.83 + sin(th) * 0.05), size))
            p.line(to: pt((0.81 + cos(th) * 0.14, 0.83 + sin(th) * 0.14), size))
            p.stroke()
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    static let cursorImage = image(size: 36)
    static let followerImage = image(size: 44)
}

/// SwiftUI 에서 쓰는 벡터 채찍
struct WhipGlyph: View {
    var size: CGFloat = 44
    var body: some View {
        Image(nsImage: WhipArt.image(size: size)).resizable().interpolation(.high).frame(width: size, height: size)
    }
}
