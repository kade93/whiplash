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
    static let cageSize = NSSize(width: 460, height: 290)
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
    var firstContentView: NSView? { windows.values.first?.contentView }
    var cageContentView: NSView? { (cage?.isVisible ?? false) ? cage?.contentView : nil }

    init(model: Model) {
        self.model = model
        let nc = NotificationCenter.default
        menuObservers = [
            nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuOpen = true },
            nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuOpen = false },
        ]
    }

    /// 지금 어항에 있는 에이전트와 창 목록을 맞춘다
    func sync(level: NSWindow.Level) {
        let wanted = (model.roaming && !model.hidden) ? model.snapshot.groups : []
        var changed = false
        if FloatingPanel.debugMouse { NSLog("EOHANG sync roaming=%d hidden=%d groups=%d windows=%d", model.roaming ? 1 : 0, model.hidden ? 1 : 0, model.snapshot.groups.count, windows.count) }
        if small != model.critterSmall {                  // 크기가 바뀌면 전부 다시 만든다
            small = model.critterSmall
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
        if cage == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let frame = NSRect(x: screen.maxX - Self.cageSize.width - 24, y: screen.minY + 24,
                               width: Self.cageSize.width, height: Self.cageSize.height)
            let c = Self.panel(frame: frame, level: level)
            c.hasShadow = true
            c.alphaValue = 1
            var root = CageView(model: model)
            root.onNoDrag = { [weak c] rects in c?.noDragRects = rects }
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            c.contentView = host
            if !c.setFrameUsingName("EohangCage") { c.setFrame(frame, display: false) }
            c.setFrameAutosaveName("EohangCage")
            cage = c
        }
        cage?.level = level
        if !(cage?.isVisible ?? false) { cage?.orderFrontRegardless() }
    }

    /// 이 창이 움직일 수 있는 왼쪽 아래 원점 범위
    private func currentBounds(for w: NSWindow?, size: NSSize) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let area: NSRect
        if model.caged, let c = cage, c.isVisible {
            area = NSRect(x: c.frame.minX + 8, y: c.frame.minY + 8,
                          width: c.frame.width - 16, height: c.frame.height - 44)
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

    // MARK: 움직임

    private func tick() {
        guard !menuOpen else { return }                 // 오른쪽 클릭 메뉴를 고르는 동안 가만히
        let now = ProcessInfo.processInfo.systemUptime
        if now - platformsAt > 2 { platformsAt = now; refreshPlatforms() }
        let groups = Dictionary(model.snapshot.groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let step = Self.speed / CGFloat(Self.fps)
        let size = Self.size(small: small)
        let caged = model.caged && (cage?.isVisible ?? false)
        if let s = summon, now > s.until { summon = nil }

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
                    let cols = max(1, Int(ceil(sqrt(Double(ids.count)))))
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
                let st = RowStatus.of(g, job: g.whipJob, memTotal: model.snapshot.memTotal, immune: model.isImmune(g),
                                      angry: model.isAngry(g.id) ? model.angry[g.id]?.line : nil)
                if !small {                                   // 이름표는 머리 위 (발이 창 윗변에 닿게)
                    Text(name(g))
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .frame(maxWidth: size.width - 6)
                    Text(st.text)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(st.hot ? Color.white : (st.color ?? Color.white.opacity(0.8)))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(st.hot ? hotColor.opacity(0.9) : Color.black.opacity(0.45)))
                        .frame(maxWidth: size.width - 6)
                        .help(rowTooltip(model, g))
                }
                Spacer(minLength: 0)
                StrikeTile(strike: model.lastStrike[g.id], angryLine: model.isAngry(g.id) ? model.angry[g.id]?.line : nil) {
                    SpriteTile(kind: g.kind, awake: g.awake,
                               bob: g.awake && model.tick % 2 == 1,
                               sweat: g.awake && g.cpu >= 1.0, cell: CritterManager.cell(small: small), chore: chore(g),
                               boxed: model.critterBox, hot: st.hot, angry: model.isAngry(g.id))
                        .scaleEffect(x: critters.facingLeft[id] == true ? -1 : 1)
                }
                .opacity(g.id == Model.ghostID ? 0.55 : 1)
                .whipHover(model.hoverWhipID == g.id)
                .sentFlash(model.lastSent[g.id])
                .overlay(alignment: .topTrailing) { WaitBadge(tone: st.tone, small: small).offset(x: small ? 6 : 8, y: small ? -6 : -8) }
                .whipTarget(g.id, on: model.canWhip(g))
                .clickTarget(g.id)
                .help(rowTooltip(model, g))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .contentShape(Rectangle())
        .contextMenu {
            if let g = model.snapshot.groups.first(where: { $0.id == id }) {
                RowMenu(model: model, group: g)
            } else {
                AquariumMenu(model: model)
            }
        }
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

// MARK: - 우리 (울타리)

struct CageView: View {
    @ObservedObject var model: Model
    var onNoDrag: ([CGRect]) -> Void = { _ in }

    private let wood = Color(hex: 0x8B5A2B)

    var body: some View {
        let n = model.snapshot.groups.count
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xEADFC8).opacity(0.93))
            Fence(wood: wood)
            HStack {
                Text(tf("우리 · %d마리", n))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(wood)
                Spacer()
                Button {
                    model.caged = false
                } label: {
                    Text("풀어주기")
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
        .frame(width: CritterManager.cageSize.width, height: CritterManager.cageSize.height)
        .contentShape(Rectangle())
        .contextMenu { AquariumMenu(model: model) }
        .coordinateSpace(name: "root")
        .onPreferenceChange(NoDragKey.self) { onNoDrag($0) }
        .help(t("끌어서 옮길 수 있어요. 애들은 이 안에서만 돌아다녀요."))
    }
}

/// 픽셀 울타리: 테두리를 따라 말뚝
struct Fence: View {
    let wood: Color
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(wood), lineWidth: 3)
            let post = CGSize(width: 4, height: 12)
            var x = r.minX + 14
            while x < r.maxX - 10 {
                ctx.fill(Path(CGRect(x: x, y: r.maxY - post.height + 1, width: post.width, height: post.height)), with: .color(wood))
                ctx.fill(Path(CGRect(x: x, y: r.minY + 24, width: post.width, height: post.height)), with: .color(wood.opacity(0.35)))
                x += 18
            }
            var y = r.minY + 36
            while y < r.maxY - 16 {
                ctx.fill(Path(CGRect(x: r.minX - 1, y: y, width: post.height, height: post.width)), with: .color(wood))
                ctx.fill(Path(CGRect(x: r.maxX - post.height + 1, y: y, width: post.height, height: post.width)), with: .color(wood))
                y += 18
            }
        }
        .allowsHitTesting(false)
    }
}
