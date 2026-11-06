import AppKit
import SwiftUI
import Combine

// MARK: - 풀어놓기: 에이전트마다 작은 투명 창 하나가 화면을 돌아다닌다
// 일하는 애는 어슬렁어슬렁 걷고, 쉬는 애는 그 자리에서 자고, 내 차례인 애는 폴짝폴짝 뛴다.
// 끌어서 옮길 수 있고, 위에서 마우스를 휘두르면 채찍, 두 번 클릭하면 그 세션 창을 앞으로.
// 「우리에 가두기」를 켜면 울타리 창 안으로 걸어 들어가 그 안에서만 논다.

final class CritterManager: ObservableObject {
    @Published private(set) var facingLeft: [String: Bool] = [:]

    static func size(small: Bool) -> NSSize { small ? NSSize(width: 52, height: 42) : NSSize(width: 140, height: 78) }
    static func cell(small: Bool) -> CGFloat { small ? 1.5 : 2.5 }
    static let alpha: CGFloat = 0.84                 // 살짝 투명
    static let cageWidth: CGFloat = 480
    /// 당근밭 창 크기: 줄 수에 따라 (2줄 = 250). 10마리 넘으면 당근 없는 줄이 아래에 늘어난다.
    static func cageSize(count: Int) -> NSSize {
        let rows = max(carrotSlots / fieldCols, Int(ceil(Double(max(count, 1)) / Double(fieldCols))))
        return NSSize(width: cageWidth, height: fieldTop + CGFloat(rows) * fieldRowPitch + 14)
    }

    // MARK: 당근밭 규칙
    // 당근은 늘 10개 (= 5시간 쿼터 10% 씩). 남은 당근 = ceil(10 × 남은 쿼터%). 오른쪽부터 뽑혀 나간다.
    // 애들은 왼쪽 당근부터 한 마리씩 앉는다 → 당근이 줄면 오른쪽 애부터 굶고, 0개면 전부 파업.
    static let carrotSlots = 10
    static let fieldCols = 5
    static let fieldTop: CGFloat = 44          // 머리글 아래부터
    static let fieldRowPitch: CGFloat = 96

    static func carrotsAlive(_ q: Quota?, enabled: Bool) -> Int {
        guard enabled, let w = q?.fiveHour else { return carrotSlots }
        return max(0, min(carrotSlots, Int(ceil(Double(carrotSlots) * w.remaining / 100 - 1e-9))))
    }

    static var fieldPitch: CGFloat { (cageWidth - 24) / CGFloat(fieldCols) }

    /// i번째 자리의 캐릭터 창 왼쪽 위 (당근밭 창 왼쪽 위 기준, SwiftUI 좌표). 10번째 넘어가면 당근 없는 셋째 줄.
    static func fieldSlotTop(_ i: Int, size: NSSize) -> CGPoint {
        let col = i % fieldCols, row = i / fieldCols
        let x = 12 + CGFloat(col) * fieldPitch + (fieldPitch - size.width) / 2
        return CGPoint(x: x.rounded(), y: (fieldTop + CGFloat(row) * fieldRowPitch).rounded())
    }

    /// 당근밭 창 안에서 당근이 심긴 자리 (SwiftUI 좌표): 발 바로 아래
    static func carrotRect(_ i: Int, size: NSSize) -> CGRect {
        let o = fieldSlotTop(i, size: size)
        let w: CGFloat = 15, h: CGFloat = 24                       // 5×8 픽셀 × 3
        return CGRect(x: o.x + size.width / 2 - w / 2, y: o.y + size.height - 6, width: w, height: h)
    }

    /// 사람이 바쁘면 스르륵 사라진다 (창은 그대로, 알파 0 + 마우스 무시). 움직임도 쉰다.
    private(set) var dodged = false
    func setDodged(_ on: Bool) {
        guard on != dodged else { return }
        dodged = on
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = on ? 0.5 : 0.35
            for w in windows.values { w.animator().alphaValue = on ? 0 : Self.alpha }
            if let c = cage { c.animator().alphaValue = on ? 0 : 1 }
        }
        for w in windows.values { w.ignoresMouseEvents = on }
        cage?.ignoresMouseEvents = on
        if on, model.hoverWhipID != nil { model.hoverWhipID = nil }
    }

    @Published private(set) var hungry: Set<String> = []       // 당근 없는 자리에 앉은 애들
    private var lastAlive: Int? = nil
    private static let fps = 15.0
    private static let speed: CGFloat = 55          // 초당 px

    private struct Mover {
        var target: CGPoint? = nil
        var pauseUntil: TimeInterval = 0
        var hopStart: TimeInterval? = nil
        var hopBaseY: CGFloat = 0
        var hopHeight: CGFloat = 12
        var nextHop: TimeInterval = 0
    }

    private let model: Model
    private var windows: [String: FloatingPanel] = [:]
    private var cursorOwners: [String: WhipCursorOwner] = [:]
    private var movers: [String: Mover] = [:]
    private var timer: Timer?
    private var cage: FloatingPanel?
    private var small = false
    private var summon: (point: CGPoint, until: TimeInterval)?
    private var platforms: [NSRect] = []             // 다른 앱 창들 (x, 윗변 y, 너비) — 그 위를 걷는다
    private var platformsAt: TimeInterval = 0
    var onChange: (() -> Void)?
    var onClick: ((String, NSPoint) -> Void)?
    var onContextMenu: ((String?, NSEvent) -> Void)?
    private var menuOpen = false                     // 메뉴가 열려 있으면 아무도 안 움직인다
    private var menuObservers: [NSObjectProtocol] = []

    var isEmpty: Bool { windows.isEmpty }

    /// 채찍 맞으면 창째로 펄쩍
    func hop(_ id: String) {
        guard let w = windows[id] else { return }
        var m = movers[id] ?? Mover()
        if m.hopStart == nil { m.hopBaseY = w.frame.origin.y }
        m.hopStart = ProcessInfo.processInfo.systemUptime
        m.hopHeight = 26
        movers[id] = m
    }

    /// 「이리 와」: 다들 마우스 커서 자리로 걸어온다 (6초 동안)
    func gatherToMouse() {
        let p = NSEvent.mouseLocation
        summon = (CGPoint(x: p.x - Self.size(small: small).width / 2, y: p.y - 10),
                  ProcessInfo.processInfo.systemUptime + 6)
        for id in movers.keys { movers[id]?.target = nil }
    }
    /// 지금 떠 있는 캐릭터 창 틀 (화면 좌표) — 휘둘러 지나간 애 찾기용
    func frames() -> [String: NSRect] {
        guard !dodged else { return [:] }
        return windows.filter { $0.value.isVisible }.mapValues { $0.frame }
    }
    var firstContentView: NSView? { windows.values.first?.contentView }
    var firstAlpha: CGFloat { windows.values.first?.alphaValue ?? -1 }
    var cageContentView: NSView? { (cage?.isVisible ?? false) ? cage?.contentView : nil }

    /// 개발용: 당근밭 창 + 그 위에 앉은 애들을 한 장으로 합성
    func fieldComposite() -> NSImage? {
        guard let c = cage, c.isVisible, let cv = c.contentView else { return nil }
        func rep(_ v: NSView) -> NSBitmapImageRep? {
            guard let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
            v.cacheDisplay(in: v.bounds, to: r); return r
        }
        let img = NSImage(size: c.frame.size)
        img.lockFocus()
        rep(cv)?.draw(in: NSRect(origin: .zero, size: c.frame.size))
        for (id, w) in windows.sorted(by: { $0.key < $1.key }) {
            guard let v = w.contentView, let r = rep(v) else { continue }
            let o = NSPoint(x: w.frame.minX - c.frame.minX, y: w.frame.minY - c.frame.minY)
            r.draw(in: NSRect(origin: o, size: w.frame.size))
            NSLog("EOHANG field seat %@ at %@ hungry=%d", id, NSStringFromPoint(o), hungry.contains(id) ? 1 : 0)
        }
        img.unlockFocus()
        return img
    }

    init(model: Model) {
        self.model = model
        let nc = NotificationCenter.default
        menuObservers = [
            nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuOpen = true },
            nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuOpen = false },
        ]
    }

    /// 지금 목록에 있는 에이전트와 창 목록을 맞춘다
    func sync(level: NSWindow.Level) {
        let wanted = (model.roaming && !model.hidden) ? model.snapshot.groups : []
        var changed = false
        if FloatingPanel.debugMouse { NSLog("EOHANG sync roaming=%d hidden=%d groups=%d windows=%d", model.roaming ? 1 : 0, model.hidden ? 1 : 0, model.snapshot.groups.count, windows.count) }
        let wantSmall = model.critterSmall || model.caged   // 당근밭에선 늘 작게 (당근 한 개에 한 마리)
        if small != wantSmall {                           // 크기가 바뀌면 전부 다시 만든다
            small = wantSmall
            removeAll()
            changed = true
        }
        let ids = Set(wanted.map { $0.id })
        for (id, _) in windows where !ids.contains(id) {
            remove(id)
            changed = true
        }
        let critterLevel = NSWindow.Level(rawValue: level.rawValue + 1)
        for g in wanted where windows[g.id] == nil {
            make(g, level: critterLevel)
            changed = true
        }
        for w in windows.values where w.level != critterLevel { w.level = critterLevel }
        syncCage(show: model.caged && !wanted.isEmpty, level: level)

        if windows.isEmpty, let t = timer {
            t.invalidate(); timer = nil
        } else if !windows.isEmpty, timer == nil {
            let t = Timer(timeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.01
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        if changed { onChange?() }
    }

    private func remove(_ id: String) {
        windows[id]?.orderOut(nil)
        windows[id]?.close()
        windows[id] = nil
        cursorOwners[id] = nil
        movers[id] = nil
        facingLeft[id] = nil
    }

    private func removeAll() { for id in Array(windows.keys) { remove(id) } }

    private static func panel(frame: NSRect, level: NSWindow.Level) -> FloatingPanel {
        let p = FloatingPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = level
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.sharingType = .readOnly
        p.alphaValue = alpha
        return p
    }

    private func make(_ g: AgentGroup, level: NSWindow.Level) {
        defer { if dodged, let w = windows[g.id] { w.alphaValue = 0; w.ignoresMouseEvents = true } }
        let size = Self.size(small: small)
        let area = currentBounds(for: nil, size: size)
        let origin = NSPoint(x: CGFloat.random(in: area.x), y: CGFloat.random(in: area.y))
        let p = Self.panel(frame: NSRect(origin: origin, size: size), level: level)

        let id = g.id
        var root = CritterView(model: model, critters: self, id: id, small: small)
        root.onNoDrag = { [weak p] rects in p?.noDragRects = rects }
        root.onWhipTargets = { [weak p] rects in p?.whipTargets = rects }
        root.onClickTargets = { [weak p] rects in p?.clickTargets = rects }
        p.onClick = { [weak self] id, pt in self?.onClick?(id, pt) }
        p.onContextMenu = { [weak self] hit, e in self?.onContextMenu?(hit ?? id, e) }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let owner = WhipCursorOwner()
        owner.panel = p
        host.addTrackingArea(NSTrackingArea(rect: .zero,
                                            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                            owner: owner, userInfo: nil))
        p.contentView = host
        p.onSwing = { [weak self] id in self?.model.whip(id: id) }
        p.onDoubleClick = { [weak self] in
            guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.id == id }) else { return }
            self.model.bringToFront(g)
        }
        p.orderFrontRegardless()
        windows[id] = p
        cursorOwners[id] = owner
        movers[id] = Mover()
    }

    // MARK: 우리

    private func syncCage(show: Bool, level: NSWindow.Level) {
        if !show {
            if let c = cage, c.isVisible { c.orderOut(nil) }
            return
        }
        let want = Self.cageSize(count: windows.count)
        if cage == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let frame = NSRect(x: screen.maxX - want.width - 24, y: screen.minY + 24, width: want.width, height: want.height)
            let c = Self.panel(frame: frame, level: level)
            c.onContextMenu = { [weak self] _, e in self?.onContextMenu?(nil, e) }
            c.hasShadow = true
            c.alphaValue = 1
            var root = FieldView(model: model)
            root.onNoDrag = { [weak c] rects in c?.noDragRects = rects }
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            c.contentView = host
            if !c.setFrameUsingName("WhiplashField") { c.setFrame(frame, display: false) }
            c.setFrameAutosaveName("WhiplashField")
            cage = c
        }
        cage?.level = level
        if let c = cage, c.frame.size != want {                  // 줄이 늘면 아래로 자란다 (윗변 고정)
            c.setFrame(NSRect(x: c.frame.minX, y: c.frame.maxY - want.height, width: want.width, height: want.height), display: true)
        }
        if !(cage?.isVisible ?? false) { cage?.orderFrontRegardless() }
    }

    /// 이 창이 움직일 수 있는 왼쪽 아래 원점 범위
    private func currentBounds(for w: NSWindow?, size: NSSize) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let area: NSRect
        if model.caged, let c = cage, c.isVisible {
            area = NSRect(x: c.frame.minX + 10, y: c.frame.minY + 8,
                          width: c.frame.width - 20, height: c.frame.height - 70)
        } else {
            area = ((w?.screen ?? NSScreen.main)?.visibleFrame ?? w?.frame) ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        }
        return (area.minX...max(area.minX, area.maxX - size.width),
                area.minY...max(area.minY, area.maxY - size.height))
    }

    // MARK: 다른 앱 창 윗변 = 발판

    private func refreshPlatforms() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { platforms = []; return }
        let me = getpid()
        let screenH = NSScreen.screens.first?.frame.height ?? 0      // CG 좌표(왼쪽 위 원점) → Cocoa(왼쪽 아래)
        var out: [NSRect] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.5,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"],
                  wd >= 240, ht >= 120 else { continue }
            out.append(NSRect(x: x, y: screenH - y, width: wd, height: ht))   // y = 윗변
            if out.count >= 10 { break }                                      // 앞쪽 창들만
        }
        platforms = out
    }

    /// 남은 당근 수가 줄면 그 자리 애가 당근을 뽑아 먹는다 (펄쩍 + 아삭). 자리에 당근이 없으면 굶는 중.
    private func updateCarrots(caged: Bool) {
        let alive = Self.carrotsAlive(model.quota, enabled: model.quotaEnabled)
        let ids = windows.keys.sorted()
        if caged, let last = lastAlive, alive < last {
            for i in alive..<last where i < ids.count { hop(ids[i]) }
            NSSound(named: "Pop")?.play()
        }
        lastAlive = alive
        let h: Set<String> = caged && model.quotaEnabled ? Set(ids.enumerated().filter { $0.offset >= alive }.map { $0.element }) : []
        if h != hungry { hungry = h }
    }

    // MARK: 움직임

    private func tick() {
        guard !menuOpen, !dodged else { return }        // 메뉴를 고르는 동안·숨어 있는 동안 가만히
        let now = ProcessInfo.processInfo.systemUptime
        if now - platformsAt > 2 { platformsAt = now; refreshPlatforms() }
        let groups = Dictionary(model.snapshot.groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let step = Self.speed / CGFloat(Self.fps)
        let size = Self.size(small: small)
        let caged = model.caged && (cage?.isVisible ?? false)
        if let s = summon, now > s.until { summon = nil }
        updateCarrots(caged: caged)

        for (id, w) in windows {
            guard !w.isDragging, let g = groups[id] else { continue }
            if model.hoverWhipID == id { continue }        // 커서가 올라가 있으면 가만히 (채찍 맞을 준비)
            var m = movers[id] ?? Mover()
            let (xr, yr) = currentBounds(for: w, size: size)
            var o = w.frame.origin
            let outside = !(xr.contains(o.x) && yr.contains(o.y))

            func walk(ignorePause: Bool) {
                if !ignorePause && now < m.pauseUntil { return }
                if let s = summon, m.target == nil {           // 부르면 커서 둘레 격자 자리로 (겹치지 않게)
                    let ids = windows.keys.sorted()
                    let i = ids.firstIndex(of: id) ?? 0
                    let cols = ids.count <= 10 ? max(1, ids.count) : max(1, Int(ceil(sqrt(Double(ids.count)))))   // 10마리까지는 한 줄로 (줄 세워 놓고 한 번에 후려치기)
                    let col = CGFloat(i % cols) - CGFloat(cols - 1) / 2, row = CGFloat(i / cols)
                    let t = CGPoint(x: min(max(s.point.x + col * (size.width + 6), xr.lowerBound), xr.upperBound),
                                    y: min(max(s.point.y - row * (size.height + 4), yr.lowerBound), yr.upperBound))
                    m.target = t
                    let left = t.x < o.x
                    if facingLeft[id] != left { facingLeft[id] = left }
                }
                if let t = m.target, xr.contains(t.x), yr.contains(t.y) {
                    let dx = t.x - o.x, dy = t.y - o.y
                    let d = hypot(dx, dy)
                    if d <= step {
                        o = t
                        m.target = nil
                        m.pauseUntil = now + Double.random(in: 1.5...5)
                    } else {
                        o.x += dx / d * step
                        o.y += dy / d * step
                    }
                } else {
                    func candidate() -> CGPoint {
                        var t = CGPoint(x: CGFloat.random(in: xr), y: CGFloat.random(in: yr))
                        // 열에 일곱은 다른 앱 창 윗변 위로 (파인더 위를 걸어 다닌다)
                        if !caged, !platforms.isEmpty, Int.random(in: 0..<10) < 7, let pf = platforms.randomElement() {
                            let lo = max(xr.lowerBound, pf.minX), hi = min(xr.upperBound, pf.maxX - size.width)
                            if lo <= hi {
                                t = CGPoint(x: CGFloat.random(in: lo...hi),
                                            y: min(max(pf.minY, yr.lowerBound), yr.upperBound))   // 발이 윗변에 닿게
                            }
                        }
                        return t
                    }
                    // 남들(자리·목표)과 가장 먼 후보를 고른다 → 몰려도 안 겹친다
                    let others = windows.filter { $0.key != id }.map { (movers[$0.key]?.target ?? $0.value.frame.origin) }
                    var best = candidate(), bestD = -1.0
                    for _ in 0..<8 {
                        let c = candidate()
                        let d = others.map { Double(hypot($0.x - c.x, $0.y - c.y)) }.min() ?? 1e9
                        if d > bestD { best = c; bestD = d }
                    }
                    let t = best
                    m.target = t
                    let left = t.x < o.x
                    if facingLeft[id] != left { facingLeft[id] = left }
                }
            }

            if caged, m.hopStart == nil, let c = cage {    // 당근밭: 왼쪽 당근부터 한 마리씩 앉는다
                let ids = windows.keys.sorted()
                let i = ids.firstIndex(of: id) ?? 0
                let rel = Self.fieldSlotTop(i, size: size)
                let slot = CGPoint(x: c.frame.minX + rel.x, y: c.frame.maxY - rel.y - size.height)
                let dx = slot.x - o.x, dy = slot.y - o.y
                let d = hypot(dx, dy)
                if d > step { o.x += dx / d * step; o.y += dy / d * step; if facingLeft[id] != (dx < 0) { facingLeft[id] = dx < 0 } }
                else { o = slot }
                o.x = o.x.rounded(); o.y = o.y.rounded()
                if o != w.frame.origin { w.setFrameOrigin(o) }
                movers[id] = m
                continue
            }
            if let hs = m.hopStart {                      // 뛰는 중이면 (채찍·내 차례) 다른 건 안 한다
                let t = now - hs
                if t >= 0.4 {
                    o.y = m.hopBaseY
                    m.hopStart = nil
                    m.hopHeight = 12
                    m.nextHop = now + 2.5
                } else {
                    o.y = m.hopBaseY + m.hopHeight * CGFloat(sin(t / 0.4 * .pi))
                }
            } else if caged && outside {                  // 우리 밖이면 자던 애도 걸어 들어간다
                walk(ignorePause: true)
            } else if summon != nil {                     // 부르면 자던 애도 온다
                walk(ignorePause: true)
            } else if g.awake {
                walk(ignorePause: false)
            } else {
                m.target = nil
                if g.session?.needsYou == true, now >= m.nextHop {   // 내 차례: 2.5초마다 폴짝
                    m.hopStart = now
                    m.hopBaseY = o.y
                    m.hopHeight = 12
                }
            }

            // 절대 겹치지 않게: 다른 애와 포개지면 가까운 축으로 밀어낸다 (틱당 최대 5px, 부드럽게)
            let minDX = size.width * 0.92, minDY = size.height * 0.85
            for (oid, ow) in windows where oid != id {
                let p = ow.frame.origin
                let dx = o.x - p.x, dy = o.y - p.y
                guard abs(dx) < minDX, abs(dy) < minDY else { continue }
                let pushX = minDX - abs(dx), pushY = minDY - abs(dy)
                if pushX <= pushY || m.hopStart != nil {
                    o.x += (dx >= 0 ? 1 : -1) * min(pushX / 2, 5)
                } else {
                    o.y += (dy >= 0 ? 1 : -1) * min(pushY / 2, 5)
                }
            }
            if m.hopStart == nil && !(caged && outside) {
                o.x = min(max(o.x, xr.lowerBound), xr.upperBound)
                o.y = min(max(o.y, yr.lowerBound), yr.upperBound)
            }
            o.x = o.x.rounded(); o.y = o.y.rounded()            // 창 원점은 정수. 반올림 안 하면 매 틱 떨린다
            if o != w.frame.origin {
                if FloatingPanel.debugMouse, model.hoverWhipID != nil {
                    NSLog("EOHANG moved %@ (hover=%@) from %@ to %@ target=%@ hop=%d caged=%d summon=%d",
                          id, model.hoverWhipID ?? "nil", NSStringFromPoint(w.frame.origin), NSStringFromPoint(o),
                          m.target.map { NSStringFromPoint($0) } ?? "nil", m.hopStart == nil ? 0 : 1, caged ? 1 : 0, summon == nil ? 0 : 1)
                }
                w.setFrameOrigin(o)
            }
            movers[id] = m
        }
    }
}

// MARK: - 크리터 한 마리

struct CritterView: View {
    @ObservedObject var model: Model
    @ObservedObject var critters: CritterManager
    let id: String
    var small = false
    var onNoDrag: ([CGRect]) -> Void = { _ in }
    var onWhipTargets: ([String: CGRect]) -> Void = { _ in }
    var onClickTargets: ([String: CGRect]) -> Void = { _ in }

    var body: some View {
        let size = CritterManager.size(small: small)
        VStack(spacing: 2) {
            if let g = model.snapshot.groups.first(where: { $0.id == id }) {
                let strike = model.onStrike(g)
                let st = RowStatus.of(g, job: g.whipJob, memTotal: model.snapshot.memTotal, immune: model.isImmune(g),
                                      angry: model.isAngry(g.id) ? model.angry[g.id]?.line : nil,
                                      strike: strike ? (g.session?.strikeUntil ?? model.quota?.fiveHour?.resetsAt ?? Date().addingTimeInterval(3600)) : nil)
                if !small {                                   // 이름표는 머리 위 (발이 창 윗변에 닿게)
                    Text(name(g))
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.current.pillText)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.current.pill))
                        .frame(maxWidth: size.width - 6)
                    Text(st.text)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(st.hot ? Color.white : (st.color ?? Theme.current.pillText.opacity(0.85)))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(st.hot ? hotColor.opacity(0.9) : Theme.current.pill.opacity(0.8)))
                        .frame(maxWidth: size.width - 6)
                        .help(rowTooltip(model, g))
                }
                Spacer(minLength: 0)
                StrikeTile(strike: model.lastStrike[g.id], angryLine: model.isAngry(g.id) ? model.angry[g.id]?.line : nil) {
                    SpriteTile(kind: g.kind, awake: g.awake,
                               bob: g.awake && model.tick % 2 == 1,
                               sweat: g.awake && g.cpu >= 1.0, cell: CritterManager.cell(small: small), chore: chore(g, strike: strike),
                               boxed: model.critterBox && !model.caged, hot: st.hot, angry: model.isAngry(g.id))
                        .scaleEffect(x: critters.facingLeft[id] == true ? -1 : 1)
                }
                .opacity(g.id == Model.ghostID ? 0.55 : 1)
                .whipHover(model.hoverWhipID == g.id)
                .sentFlash(model.lastSent[g.id])
                .overlay(alignment: .topTrailing) { WaitBadge(tone: st.tone, small: small).offset(x: small ? 6 : 8, y: small ? -6 : -8) }
                .overlay(alignment: .bottomLeading) {
                    if critters.hungry.contains(g.id) && !strike {
                        Text("🥕✕").font(.system(size: 8)).padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .help(t("자리에 당근이 없어요 — 쿼터가 줄어 굶는 중"))
                    }
                }
                .whipTarget(g.id, on: model.canWhip(g))
                .clickTarget(g.id)
                .help(rowTooltip(model, g))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .contentShape(Rectangle())
        .coordinateSpace(name: "root")
        .onPreferenceChange(NoDragKey.self) { onNoDrag($0) }
        .onPreferenceChange(WhipTargetKey.self) { onWhipTargets($0) }
        .onPreferenceChange(ClickTargetKey.self) { onClickTargets($0) }
    }

    private func name(_ g: AgentGroup) -> String {
        if g.id == Model.ghostID { return t("Claude (꺼짐) · 휘두르면 깨워요") }
        if let s = g.session, !s.name.isEmpty { return s.name }
        return g.kind.title + " · " + g.label
    }
}

// MARK: - 당근밭 (애들을 마리수만큼 박아 두는 곳)

struct FieldView: View {
    @ObservedObject var model: Model
    var onNoDrag: ([CGRect]) -> Void = { _ in }

    private let soil = Color(hex: 0x9C6B3C)
    private let soilDark = Color(hex: 0x7A5230)
    private let wood = Color(hex: 0x6E4322)

    var body: some View {
        let n = model.snapshot.groups.count
        let five = model.quota?.fiveHour
        let alive = CritterManager.carrotsAlive(model.quota, enabled: model.quotaEnabled)
        let hungry = max(0, n - alive)
        let size = CritterManager.size(small: true)
        let cageSize = CritterManager.cageSize(count: n)
        let rows = Int((cageSize.height - CritterManager.fieldTop - 14) / CritterManager.fieldRowPitch)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(soil.opacity(0.95))
            // 두둑: 줄마다 가로 흙더미, 자리마다 당근 (뽑히면 흙만)
            Canvas { ctx, sz in
                for row in 0..<rows {
                    let y = CritterManager.fieldTop + CGFloat(row) * CritterManager.fieldRowPitch + size.height + 8
                    ctx.fill(Path(roundedRect: CGRect(x: 10, y: y, width: sz.width - 20, height: 14), cornerRadius: 7), with: .color(soilDark.opacity(0.8)))
                }
                ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: sz).insetBy(dx: 2, dy: 2), cornerRadius: 11), with: .color(wood), lineWidth: 3)
            }
            .allowsHitTesting(false)
            ForEach(0..<CritterManager.carrotSlots, id: \.self) { i in
                let r = CritterManager.carrotRect(i, size: size)
                PixelArt(rows: i < alive ? ToolArt.carrot : ToolArt.carrotEaten, cell: 3)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            .allowsHitTesting(false)
            // 자리마다 누가 얼마나 먹었나: 🥕1.4 · $39 (세션 먹이값 비율)
            let seated = model.snapshot.groups.sorted { $0.id < $1.id }
            ForEach(Array(seated.enumerated()), id: \.element.id) { i, g in
                let o = CritterManager.fieldSlotTop(i, size: size)
                let pitch = CritterManager.fieldPitch
                Text(seatLabel(g))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFF1DC).opacity(0.9))
                    .lineLimit(1)
                    .frame(width: pitch - 6)
                    .offset(x: o.x + size.width / 2 - (pitch - 6) / 2, y: o.y + size.height + 24)
                    .help(rowTooltip(model, g))
            }
            .allowsHitTesting(false)
            HStack {
                Text(model.quotaEnabled && five != nil
                     ? (model.quota?.summary ?? "") + (hungry > 0 ? tf(" · %d마리 굶는 중", hungry) : "")
                     : tf("당근밭 · %d마리", n))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFF1DC))
                Spacer()
                Button {
                    model.caged = false
                } label: {
                    Text(t("뽑아주기"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(wood))
                }
                .buttonStyle(.plain)
                .noDrag()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .frame(width: cageSize.width, height: cageSize.height)
        .contentShape(Rectangle())
        .coordinateSpace(name: "root")
        .onPreferenceChange(NoDragKey.self) { onNoDrag($0) }
        .help(t("끌어서 옮길 수 있어요. 애들은 여기 자기 자리에 박혀 있어요."))
    }

    private func seatLabel(_ g: AgentGroup) -> String {
        guard let s = g.session else { return g.kind.title }
        var parts: [String] = []
        if let c = model.carrotsEaten(g) { parts.append(String(format: "🥕%.1f", c)) }
        if s.costUSD > 0 { parts.append(fmtUSD(s.costUSD)) }
        if parts.isEmpty { parts.append(s.name.isEmpty ? g.label : s.name) }
        return parts.joined(separator: " · ")
    }
}
