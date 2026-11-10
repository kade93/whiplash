import AppKit
import SwiftUI
import Combine

@main
@MainActor
enum WhiplashApp {
    static func main() {
        migratePreferences()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)      // 시작은 조용히. Dock 아이콘은 설정(dockIcon)에 따라 켠다
        withExtendedLifetime(delegate) { app.run() }
    }

    /// 0.3 까지는 번들 ID 가 kr.urbanism.whiplash 였다. 새 설정이 비어 있고 옛 설정이 있으면 한 번 옮겨 온다.
    private static func migratePreferences() {
        let d = UserDefaults.standard
        guard d.object(forKey: "lang") == nil, d.object(forKey: "compact") == nil,
              let old = UserDefaults(suiteName: "kr.urbanism.whiplash")?.persistentDomain(forName: "kr.urbanism.whiplash"),
              !old.isEmpty else { return }
        for (k, v) in old where !k.hasPrefix("NS") { d.set(v, forKey: k) }
    }
}

/// 테두리 없는 작은 창. 왼쪽 클릭으로 끌어서 옮기고, 두 번 클릭하면 작게/크게.
/// 버튼 자리(noDragRects, 창 왼쪽 위 기준)는 클릭을 그대로 버튼에 넘긴다.
/// 쉬는 캐릭터 자리(whipTargets) 위에서 마우스를 빠르게 왕복하면 채찍질.
final class FloatingPanel: NSPanel {
    var onDoubleClick: (() -> Void)?
    var onSwing: ((String) -> Void)?
    var onPet: ((String) -> Void)?                   // 천천히 쓱쓱 쓰다듬기 → 간식
    private var pets: [String: [TimeInterval]] = [:]
    private var lastPet: [String: TimeInterval] = [:]
    var onClick: ((String, NSPoint) -> Void)?        // 제자리 클릭한 칸 id, 화면 좌표
    var onContextMenu: ((String?, NSEvent) -> Void)? // 오른쪽 클릭: 칸 id(없으면 nil) — SwiftUI 메뉴 대신 NSMenu (깜빡임 방지)
    var noDragRects: [CGRect] = []
    var whipTargets: [String: CGRect] = [:]
    var clickTargets: [String: CGRect] = [:]
    private(set) var isDragging = false
    private var downAt: (point: NSPoint, time: TimeInterval)?

    private var lastMove: (t: TimeInterval, p: CGPoint)?
    private var passes: [String: [TimeInterval]] = [:]
    private var lastSwing: [String: TimeInterval] = [:]
    private var enteredAt: [String: TimeInterval] = [:]   // 캐릭터 근처에 들어온 시각 (머문 뒤에만 채찍)
    var optionHeld = false
    var needsOption = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static let debugMouse = ProcessInfo.processInfo.environment["WHIPLASH_DEBUG_MOUSE"] != nil

    /// 전역 마우스 모니터가 화면 좌표로 넣어 준다 (키 창이 아니어도 받게)
    func trackSwing(screen p: NSPoint, time t: TimeInterval) {
        guard isVisible, frame.insetBy(dx: -30, dy: -30).contains(p) else { lastMove = nil; enteredAt = [:]; return }
        // 위에 다른 창(어느 앱이든)이 덮여 있으면 그 자리는 안 맞는다
        if frame.contains(p), NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0) != windowNumber { lastMove = nil; return }
        trackSwing(local: CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y), time: t)
    }

    /// 지금 커서가 채찍 맞을 캐릭터 위에 있으면 그 칸 id
    func whipTargetID(screen p: NSPoint) -> String? {
        guard isVisible, frame.contains(p) else { return nil }
        let local = CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y)
        return whipTargets.first { $0.value.insetBy(dx: -4, dy: -4).contains(local) }?.key
    }

    override func sendEvent(_ event: NSEvent) {
        // 오른쪽 클릭(또는 ⌃-클릭): SwiftUI contextMenu 대신 AppKit 메뉴 (모델이 바뀌어도 안 깜빡인다)
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
           let handler = onContextMenu {
            handler(hitTarget(event.locationInWindow), event)
            return
        }
        if event.type == .leftMouseDown && !event.modifierFlags.contains(.control) && !onButton(event) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                let before = frame.origin
                let screenPoint = NSEvent.mouseLocation
                downAt = (screenPoint, event.timestamp)
                isDragging = true
                performDrag(with: event)
                isDragging = false
                // 끌지 않고 제자리에서 뗐으면 클릭
                if NSEvent.pressedMouseButtons & 1 == 0, hypot(frame.origin.x - before.x, frame.origin.y - before.y) < 3 {
                    downAt = nil
                    click(at: event.locationInWindow, screen: screenPoint)
                }
            }
            return
        }
        if event.type == .leftMouseUp, let d = downAt {        // performDrag 가 비동기인 경우를 대비
            downAt = nil
            let p = NSEvent.mouseLocation
            if event.timestamp - d.time < 0.5, hypot(p.x - d.point.x, p.y - d.point.y) < 3 {
                click(at: event.locationInWindow, screen: p)
            }
        }
        super.sendEvent(event)
    }

    private func hitTarget(_ local: NSPoint) -> String? {
        guard let height = contentView?.bounds.height else { return nil }
        let flipped = CGPoint(x: local.x, y: height - local.y)
        return clickTargets.first { $0.value.insetBy(dx: -2, dy: -2).contains(flipped) }?.key
    }

    private func click(at local: NSPoint, screen: NSPoint) {
        guard let height = contentView?.bounds.height else { return }
        let flipped = CGPoint(x: local.x, y: height - local.y)
        if let hit = clickTargets.first(where: { $0.value.insetBy(dx: -2, dy: -2).contains(flipped) }) {
            onClick?(hit.key, screen)
        }
    }

    /// 채찍질 = 캐릭터 위에 0.25초 머문 뒤(채찍 커서가 뜬 뒤), 가운데 선을 0.8초 안에 두 번 빠르게(초당 400px 이상) 가로지르기 (가로든 세로든).
    /// 그냥 스쳐 지나가는 건 머물지도 않았고 한 번뿐이라 안 맞는다. 「⌥ 누른 채로만」을 켰으면 ⌥ 도 필요하다.
    private func trackSwing(local p: CGPoint, time t: TimeInterval) {
        if Self.debugMouse { NSLog("EOHANG move %@ targets=%d", NSStringFromPoint(p), whipTargets.count) }
        defer { lastMove = (t, p) }
        // 머문 시간: 캐릭터 둘레에 들어온 시각을 기억한다. 창을 아예 벗어나야 잊는다 (휘두르는 동안은 유지)
        for (id, r) in whipTargets where enteredAt[id] == nil && r.insetBy(dx: -28, dy: -28).contains(p) {
            enteredAt[id] = t
        }
        guard !whipTargets.isEmpty, let last = lastMove, t > last.t, t - last.t < 0.2 else { return }
        if needsOption && !optionHeld { return }
        let speed = hypot(p.x - last.p.x, p.y - last.p.y) / (t - last.t)
        // 쓰다듬기: 느리게(초당 30~180px) 가운데 선을 2.5초 안에 세 번 넘으면 간식. 빠르면 채찍.
        if speed >= 30 && speed < 180 {
            for (id, r) in whipTargets {
                let ax = last.p.x - r.midX, bx = p.x - r.midX
                let band = r.insetBy(dx: -4, dy: -10)
                let midY = (p.y + last.p.y) / 2
                guard midY >= band.minY, midY <= band.maxY, (ax < 0 && bx >= 0) || (ax > 0 && bx <= 0) else { continue }
                guard let entered = enteredAt[id], t - entered >= 0.25 else { continue }
                var list = (pets[id] ?? []).filter { t - $0 < 2.5 }
                list.append(t)
                if list.count >= 3, t - (lastPet[id] ?? 0) > 3 {
                    lastPet[id] = t; list = []
                    if Self.debugMouse { NSLog("EOHANG pet! %@", id) }
                    onPet?(id)
                }
                pets[id] = list
            }
            return
        }
        guard speed >= 400 else { return }

        for (id, r) in whipTargets {
            // 가로로 휙휙(세로 가운데 선을 넘음) 또는 세로로 휙휙(가로 가운데 선을 넘음) — 줄 세워 놓으면 세로로 치는 게 편하다
            let bandX = r.insetBy(dx: -4, dy: -14), bandY = r.insetBy(dx: -14, dy: -4)
            let midY = (p.y + last.p.y) / 2, midX = (p.x + last.p.x) / 2
            let ax = last.p.x - r.midX, bx = p.x - r.midX
            let ay = last.p.y - r.midY, by = p.y - r.midY
            let crossX = midY >= bandX.minY && midY <= bandX.maxY && ((ax < 0 && bx >= 0) || (ax > 0 && bx <= 0))
            let crossY = midX >= bandY.minX && midX <= bandY.maxX && ((ay < 0 && by >= 0) || (ay > 0 && by <= 0))
            guard crossX || crossY else { continue }                            // 가운데 선에 딱 걸친 샘플도 가로지른 것
            guard let entered = enteredAt[id], t - entered >= 0.25 else {
                if Self.debugMouse { NSLog("EOHANG cross %@ rejected: dwell %.2f", id, enteredAt[id].map { t - $0 } ?? -1) }
                continue
            }
            var list = (passes[id] ?? []).filter { t - $0 < 0.8 }
            list.append(t)
            if Self.debugMouse { NSLog("EOHANG cross %@ ok passes=%d", id, list.count) }
            if list.count >= 2, t - (lastSwing[id] ?? 0) > 1.5 {
                lastSwing[id] = t
                list = []
                if Self.debugMouse { NSLog("EOHANG swing! %@", id) }
                onSwing?(id)
            }
            passes[id] = list
        }
    }

    private func onButton(_ event: NSEvent) -> Bool {
        guard let height = contentView?.bounds.height else { return false }
        let p = event.locationInWindow
        let flipped = CGPoint(x: p.x, y: height - p.y)
        return noDragRects.contains { $0.insetBy(dx: -2, dy: -2).contains(flipped) }
    }
}

/// 닫힘 동작이 있는 메뉴 항목 (메뉴 막대 메뉴용)
final class ActionItem: NSMenuItem {
    var handler: () -> Void = {}
    @objc func run(_ sender: Any?) { handler() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: FloatingPanel!
    var welcome: NSPanel?
    private var host: NSHostingView<WidgetView>!
    private var effectView: NSVisualEffectView!
    private var solidView: NSView!
    let model = Model()
    private var critters: CritterManager!
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()
    private var mouseMonitors: [Any] = []
    private var whipCursorShown = false
    // 바쁨 감지: 최근 3초 마우스 이동 거리 + 마지막 키 입력·스크롤 시각
    private var mouseTrail: [(t: TimeInterval, d: CGFloat)] = []
    private var lastMouse: NSPoint? = nil
    // 휘둘러 지나가기: 빠르게 지나간 캐릭터들을 모아 한 번에 때린다
    private var sweepTrail: [(t: TimeInterval, p: NSPoint)] = []
    private var sweepHits: [String] = []
    private var sweepCooldownUntil: TimeInterval = 0
    private var busySince: TimeInterval? = nil
    private var quietSince: TimeInterval? = nil
    private var busyTimer: Timer?
    private var cursorFollower: NSPanel?
    private var prompt: PromptPanel?
    private var occlusionObserver: NSObjectProtocol?
    private var modelSub: AnyCancellable?
    private var refitPending = false

    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    private static let autosaveName = "WhiplashPanel"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 이미 떠 있으면 하나만
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 240),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = model.alwaysOnTop ? .floating : Self.desktopLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .readOnly            // 화면 캡처·화면 공유에 보이게
        self.panel = panel

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 14)
        panel.contentView = effect
        let solid = NSView()                                   // 단색 테마용 덮개
        solid.wantsLayer = true
        solid.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(solid)
        NSLayoutConstraint.activate([
            solid.leadingAnchor.constraint(equalTo: effect.leadingAnchor), solid.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            solid.topAnchor.constraint(equalTo: effect.topAnchor), solid.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        self.effectView = effect
        self.solidView = solid

        var root = WidgetView(model: model)
        root.onNoDrag = { [weak panel] rects in panel?.noDragRects = rects }
        root.onWhipTargets = { [weak panel] rects in panel?.whipTargets = rects }
        root.onClickTargets = { [weak panel] rects in panel?.clickTargets = rects }
        panel.onSwing = { [weak self] id in self?.model.whip(id: id) }
        panel.onPet = { [weak self] id in self?.model.treat(id: id) }
        panel.onClick = { [weak self] id, p in self?.openPrompt(for: id, near: p) }
        panel.onContextMenu = { [weak self] id, e in self?.showContextMenu(for: id, event: e) }
        effect.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                              owner: effect, userInfo: nil))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]     // 내용의 이상적인 크기를 알려 준다
        self.host = host
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
        ])

        if !panel.setFrameUsingName(Self.autosaveName), let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: v.maxX - panel.frame.width - 16, y: v.maxY - 16))
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        panel.orderFrontRegardless()

        panel.onDoubleClick = { [weak self] in self?.model.compact.toggle() }

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibility() }
        }

        critters = CritterManager(model: model)
        critters.onChange = { [weak self] in self?.refreshVisibility() }
        critters.onClick = { [weak self] id, p in self?.openPrompt(for: id, near: p) }
        critters.onContextMenu = { [weak self] id, e in self?.showContextMenu(for: id, event: e) }
        if let text = ProcessInfo.processInfo.environment["WHIPLASH_SEND_TEST"] {      // 개발용: 6초 뒤 첫 세션에 보내 본다
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.session != nil }) else { NSLog("EOHANG send-test: 세션 없음"); return }
                self.model.send(text, to: g) { r in NSLog("EOHANG send-test %@ → %@", g.id, String(describing: r)) }
            }
        }
        makeStatusItem()
        makeMainMenu()
        reloadHotKeysIfChanged()
        installMouseMonitor()
        startBusyDetector()
        installBodyWhips()
        model.onDockIconChange = { on in NSApp.setActivationPolicy(on ? .regular : .accessory) }
        if model.dockIcon { NSApp.setActivationPolicy(.regular) }
        if Paths.sandboxed && !Paths.hasHomeAccess && ProcessInfo.processInfo.environment["WHIPLASH_NO_PROMPT"] == nil {
            Paths.requestHomeAccess()
        }
        NSLog("Whiplash sandboxed=%d homeAccess=%d home=%@", Paths.sandboxed ? 1 : 0, Paths.hasHomeAccess ? 1 : 0, Paths.home)
        if ProcessInfo.processInfo.environment["WHIPLASH_DEBUG_PROC"] != nil { ProcessProbe.log() }
        if ProcessInfo.processInfo.environment["WHIPLASH_DEBUG_SOCK"] != nil {      // 개발용: 세션 소켓에 connect 만 (아무것도 안 보냄)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let s = self?.model.snapshot.groups.compactMap({ $0.session }).first(where: { $0.socketPath != nil }),
                      let path = s.socketPath else { NSLog("EOHANG sock-probe: 세션 없음 (homeAccess=%d)", Paths.hasHomeAccess ? 1 : 0); return }
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
                _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    path.utf8CString.withUnsafeBufferPointer { src in
                        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in for (i, c) in src.enumerated() where i < 104 { dst[i] = c } }
                    }
                }
                let r = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
                NSLog("EOHANG sock-probe %@ connect=%d errno=%d (%@)", path, r, errno, String(cString: strerror(errno)))
                close(fd)
            }
        }

        model.onStrike = { [weak self] id in self?.critters.hop(id) }
        model.onThemeChange = { [weak self] th in self?.applyTheme(th) }
        applyTheme(Theme.current)
        model.onLevelChange = { [weak self] onTop in
            guard let self = self else { return }
            self.panel?.level = self.level
            self.critters.sync(level: self.level)
        }
        // 내용이 바뀔 때마다 (한 번에 묶어서) 창 크기를 내용에 맞추고 크리터 창 목록을 맞춘다
        modelSub = model.objectWillChange.sink { [weak self] _ in self?.scheduleRefit() }
        model.start()
        scheduleRefit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showWelcomeIfNeeded() }

        // 개발용: WHIPLASH_SNAPSHOT=/경로.png 로 띄우면 5초 뒤 화면을 그 파일로 저장
        if ProcessInfo.processInfo.environment["WHIPLASH_SWING_TEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.swingTest() }
        }
        if ProcessInfo.processInfo.environment["WHIPLASH_DODGE_TEST"] != nil {         // 개발용: 3초 뒤부터 4초간 마우스가 바쁜 척 → 숨고, 8초 조용하면 돌아오는지
            for i in 0..<8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(i) * 0.5) { [weak self] in
                    self?.mouseTrail.append((ProcessInfo.processInfo.systemUptime, 400))
                }
            }
            for sec in [2.0, 6.0, 8.0, 12.0, 17.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + sec) { [weak self] in
                    guard let self = self else { return }
                    NSLog("EOHANG dodge-test t=%.0f dodged=%d alpha=%.2f active=%d", sec, self.critters.dodged ? 1 : 0, self.critters.firstAlpha, NSApp.isActive ? 1 : 0)
                }
            }
        }
        if ProcessInfo.processInfo.environment["WHIPLASH_WHIPALL_TEST"] != nil {       // 개발용: 4초 뒤 전부 채찍 (DRY_WHIP 과 같이)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.model.whipAll() }
        }
        if ProcessInfo.processInfo.environment["WHIPLASH_PROMPT_TEST"] != nil {        // 개발용: 4초 뒤 첫 세션 입력창 열기
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.session != nil }) else { return }
                self.openPrompt(for: g.id, near: NSPoint(x: 600, y: 500))
            }
        }
        if ProcessInfo.processInfo.environment["WHIPLASH_ANGRY_TEST"] != nil {        // 개발용: 내 차례인 세션을 두 번 때려 화내는 모습
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.session?.needsYou == true }) else { NSLog("EOHANG angry-test: 대상 없음"); return }
                self.model.whip(g); self.model.whip(g)
            }
        }
        if let path = ProcessInfo.processInfo.environment["WHIPLASH_SNAPSHOT"] {
            let delay = Double(ProcessInfo.processInfo.environment["WHIPLASH_SNAPSHOT_DELAY"] ?? "") ?? 5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.saveSnapshot(to: path) }
        }
    }

    /// 개발용: WHIPLASH_SWING_TEST=1 이면 6초 뒤 첫 쉬는 캐릭터 위로 가짜 마우스 이벤트를 보내 감지만 확인 (채찍은 안 때림)
    private func swingTest() {
        guard let panel = panel, let (id, r) = panel.whipTargets.first else { NSLog("EOHANG swing-test: 대상 없음"); return }
        panel.onSwing = { hit in NSLog("EOHANG swing-test: 감지 %@ (기대 %@)", hit, id) }
        let h = panel.contentView!.bounds.height
        var t = ProcessInfo.processInfo.systemUptime
        for x in [r.minX - 20, r.maxX + 20, r.minX - 20, r.maxX + 20] {
            t += 0.05
            let e = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: x, y: h - r.midY), modifierFlags: [],
                                       timestamp: t, windowNumber: panel.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 0, pressure: 0)!
            panel.sendEvent(e)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {}

    private func saveSnapshot(to path: String) {
        func save(_ v: NSView?, _ file: String) {
            guard let v = v, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
        }
        save(panel?.contentView, path)
        save(critters.firstContentView, (path as NSString).deletingPathExtension + "-critter.png")
        for (i, v) in critters.allContentViews.enumerated() { save(v, (path as NSString).deletingPathExtension + "-critter\(i + 1).png") }
        save(critters.cageContentView, (path as NSString).deletingPathExtension + "-cage.png")
        if let img = critters.fieldComposite(), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-field.png"))
        }
        save(prompt?.contentView, (path as NSString).deletingPathExtension + "-prompt.png")
        save(welcome?.contentView, (path as NSString).deletingPathExtension + "-welcome.png")
        if let b = statusItem?.button {
            NSLog("EOHANG status button frame=%@ window=%@ image=%@ template=%d visible=%d",
                  NSStringFromRect(b.frame), b.window.map { NSStringFromRect($0.frame) } ?? "nil",
                  b.image.map { NSStringFromSize($0.size) } ?? "nil", b.image?.isTemplate == true ? 1 : 0, statusItem?.isVisible == true ? 1 : 0)
            save(b, (path as NSString).deletingPathExtension + "-status.png")
            if let img = b.image, let tiff = img.tiffRepresentation {
                try? tiff.write(to: URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-statusimg.tiff"))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopJobs()
    }

    private var level: NSWindow.Level { model.alwaysOnTop ? .floating : Self.desktopLevel }

    private func scheduleRefit() {
        guard !refitPending else { return }
        refitPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refitPending = false
            self.critters.sync(level: self.level)
            guard self.panel.isVisible else { return }
            self.host.layoutSubtreeIfNeeded()
            self.fit(self.host.intrinsicContentSize)
        }
    }

    /// 풀어놓았고 크리터가 하나라도 있으면 채찍질 창은 숨긴다. 「모두 숨기기」면 전부 숨긴다.
    /// 재는 박자는 크리터가 보이는 동안도 빠르게.
    private func refreshVisibility() {
        guard let panel = panel else { return }
        let roamingOut = model.roaming && !critters.isEmpty
        let hidePanel = model.hidden || (roamingOut && !model.panelWithCritters)
        if hidePanel {
            if panel.isVisible { panel.orderOut(nil) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            scheduleRefit()
        }
        model.setVisible(!model.hidden && (roamingOut || panel.occlusionState.contains(.visible)))
    }

    // MARK: 오른쪽 클릭 메뉴 (AppKit)
    // SwiftUI contextMenu 는 모델이 바뀔 때마다 다시 그려져 깜빡인다. NSMenu 는 열린 채로 고정.

    func showContextMenu(for id: String?, event: NSEvent) {
        guard let window = event.window, let view = window.contentView else { return }
        let menu = NSMenu()
        let m = model
        if let id = id, let g = m.snapshot.groups.first(where: { $0.id == id }) {
            if g.id == Model.ghostID {
                menu.addItem(menuItem(t("Open Claude app")) { m.wakeClaude(dir: nil) })
                let term = NSMenu()
                for d in m.recentProjects() { term.addItem(menuItem((d as NSString).lastPathComponent) { m.wakeClaude(dir: d) }) }
                term.addItem(.separator())
                term.addItem(menuItem(t("In home folder")) { m.wakeClaude(dir: Paths.home) })
                menu.addItem(submenu(t("Open claude in Terminal"), term))
            } else {
                let head = NSMenuItem(title: g.session.map { $0.name.isEmpty ? g.label : $0.name } ?? g.label, action: nil, keyEquivalent: "")
                head.isEnabled = false
                menu.addItem(head)
                if m.canWhip(g), !g.id.hasPrefix("app:"), !Paths.sandboxed {
                    let tasks = NSMenu()
                    for task in m.tasks { tasks.addItem(menuItem(task.title) { m.whip(g, task: task) }) }
                    menu.addItem(submenu(t("Whip — pick a task"), tasks))
                }
                if g.session != nil { menu.addItem(menuItem(t("🥕 Give a treat (praise)")) { m.treat(g) }) }
                menu.addItem(menuItem(t("Bring window to front")) { m.bringToFront(g) })
                if g.dir != nil || g.session != nil { menu.addItem(menuItem(t("Open folder")) { m.openFolder(g) }) }
                if let s = g.session {
                    menu.addItem(menuItem(t("Whip immunity"), on: m.isImmune(g)) { m.toggleImmune(g) })
                    if s.status == .busy && !s.isDesktop && !Paths.sandboxed {
                        menu.addItem(menuItem(t("Stop current work (Ctrl-C)")) { m.interrupt(g) })
                    }
                    let more = NSMenu()
                    if !s.lastPrompt.isEmpty { more.addItem(menuItem(t("Copy last prompt")) { m.copyPrompt(g) }) }
                    if s.transcript != nil { more.addItem(menuItem(t("Open transcript file")) { m.openTranscript(g) }) }
                    if more.items.count > 0 { menu.addItem(submenu(t("More"), more)) }
                }
            }
            menu.addItem(.separator())
        }
        if m.roaming {
            menu.addItem(menuItem(m.caged ? t("Pull out of the field") : t("Plant in the carrot field"), key: .cage) { m.caged.toggle() })
            menu.addItem(menuItem(t("Gather into the window"), key: .roam) { m.roaming = false })
        } else {
            menu.addItem(menuItem(t("Let loose — roam the screen"), key: .roam) { m.roaming = true; m.hidden = false })
        }
        menu.addItem(menuItem(t("Hide all"), key: .hide) { m.hidden = true })
        menu.addItem(.separator())
        menu.addItem(submenu("Settings", settingsMenu()))
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = sub
        return i
    }

    /// 확성기: 입력창을 모두에게 보내기 모드로 연다 (커서 자리)
    func openMegaphone() {
        model.hidden = false
        openPrompt(for: Model.broadcastID, near: NSEvent.mouseLocation)
    }

    // MARK: 지시 입력창

    /// 캐릭터를 제자리 클릭하면 그 위에 작은 입력창. 엔터로 보내고 esc 로 닫는다.
    func openPrompt(for id: String, near p: NSPoint) {
        guard id == Model.broadcastID || model.snapshot.groups.first(where: { $0.id == id })?.session != nil else {
            NSSound(named: "Basso")?.play()      // Claude Code 세션이 아니면 보낼 데가 없다
            return
        }
        prompt?.orderOut(nil)
        let panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        let host = NSHostingView(rootView: PromptView(model: model, groupID: id, close: { [weak panel] in panel?.orderOut(nil) }))
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor), host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor), host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        host.layoutSubtreeIfNeeded()
        let size = host.intrinsicContentSize
        var origin = NSPoint(x: p.x - size.width / 2, y: p.y + 28)
        if let s = NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, s.minX + 8), s.maxX - size.width - 8)
            if origin.y + size.height > s.maxY - 8 { origin.y = p.y - size.height - 28 }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        prompt = panel
    }

    // MARK: 마우스 휘두르기 (전역)
    // 앱이 활성이 아니어도, 창이 키 창이 아니어도 마우스 움직임을 받아 채찍질을 알아챈다.

    private func installMouseMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] e in self?.mouseMoved(e) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) { mouseMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { e in handler(e); return e }) { mouseMonitors.append(l) }
        // 두 손가락 튕김: 캐릭터 창이 커서 아래에 있으면 스크롤 이벤트가 우리 창으로 온다 (앱이 뒤에 있어도)
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] e in (self?.flick(e) ?? false) ? nil : e }) { mouseMonitors.append(l) }
    }

    // MARK: 두 손가락 튕김 — 캐릭터 위에서 트랙패드를 휙 튕기면 채찍. 길게 튕기면(260px 이상) 같은 줄에 선 애들 전부.
    private var flickAcc: CGFloat = 0
    private var flickFired = false
    private var flickCooldownUntil: TimeInterval = 0

    /// true 면 이벤트를 먹는다 (밑 창이 스크롤되지 않게)
    private func flick(_ e: NSEvent) -> Bool {
        guard e.hasPreciseScrollingDeltas else { return false }                      // 트랙패드만 (마우스 휠 제외)
        let m = model
        if model.whipNeedsOption && !e.modifierFlags.contains(.option) { return false }
        switch e.phase {
        case .began: flickAcc = 0; flickFired = false
        case .changed: flickAcc += e.scrollingDeltaX
        case .ended, .cancelled: flickAcc = 0; flickFired = false; return false
        default: break
        }
        if e.momentumPhase != [] { return false }
        let p = NSEvent.mouseLocation
        let frames = critters.frames()
        let overID = frames.first { $0.value.contains(p) }?.key
            ?? NSApp.windows.compactMap { ($0 as? FloatingPanel)?.whipTargetID(screen: p) }.first
        guard let id = overID else { return false }
        // 포인터 아래 맨 위 창이 우리 창이 아니면(다른 창이 덮음) 무시
        let top = NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0)
        guard NSApp.window(withWindowNumber: top) != nil else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= flickCooldownUntil else { return true }
        let mag = abs(flickAcc)
        if !flickFired, mag >= 60 {
            flickFired = true
            flickCooldownUntil = now + 0.8
            if FloatingPanel.debugMouse { NSLog("EOHANG flick %@ acc=%.0f", id, flickAcc) }
            m.whip(id: id)
        } else if flickFired, mag >= 260, let f = frames[id] {
            // 길게 튕기면 같은 줄 (세로로 겹치는 창) 전부
            let row = frames.filter { $0.value.minY < f.maxY && $0.value.maxY > f.minY && $0.key != id }.map { $0.key }
            if !row.isEmpty {
                flickCooldownUntil = now + 1.2
                flickAcc = 0
                if FloatingPanel.debugMouse { NSLog("EOHANG flick row → %@", row.joined(separator: ",")) }
                m.whipMany(row)
            }
        }
        return true
    }

    private func mouseMoved(_ e: NSEvent) {
        let p = NSEvent.mouseLocation
        let t = ProcessInfo.processInfo.systemUptime      // 이벤트 시각 대신 (가짜 이벤트는 0일 수 있다)
        if let l = lastMouse { mouseTrail.append((t, hypot(p.x - l.x, p.y - l.y))) }
        trackSweep(from: lastMouse, to: p, time: t, option: e.modifierFlags.contains(.option))
        lastMouse = p
        var overID: String? = nil
        let option = e.modifierFlags.contains(.option)
        for w in NSApp.windows {
            guard let fp = w as? FloatingPanel else { continue }
            fp.optionHeld = option
            fp.needsOption = model.whipNeedsOption
            fp.trackSwing(screen: p, time: t)
            if overID == nil, let id = fp.whipTargetID(screen: p) { overID = id }
        }
        // 비활성 앱은 시스템 커서를 못 바꾼다. 대신 커서 옆에 채찍을 띄우고 캐릭터를 반짝이게 한다.
        if model.hoverWhipID != overID {
            model.hoverWhipID = overID
            if FloatingPanel.debugMouse { NSLog("EOHANG hover → %@", overID ?? "nil") }
        }
        let over = overID != nil
        if over {
            moveFollower(to: p)
            WhipCursor.cursor.set()            // 뒤에 있는 앱은 커서를 못 바꿀 때가 많다 — 그래도 움직일 때마다 다시 시도
        }
        if over != whipCursorShown {
            whipCursorShown = over
            if !over { NSCursor.arrow.set(); cursorFollower?.orderOut(nil) }
        }
    }

    // MARK: 휘둘러 지나가기 — 줄 세워 놓은 애들 위로 마우스를 한 번 크게 휘두르면 지나간 애 전부 채찍
    // 0.5초 안에 700px/s 이상으로 움직이며 캐릭터 두 마리 이상을 지나가면 발동. 한 마리는 기존 방식(머문 뒤 세 번).

    static let sweepSpeed: CGFloat = 700
    static let sweepWindow: TimeInterval = 0.5

    private func trackSweep(from a: NSPoint?, to b: NSPoint, time t: TimeInterval, option: Bool) {
        sweepTrail.append((t, b))
        sweepTrail.removeAll { t - $0.t > Self.sweepWindow }
        guard let a = a, t >= sweepCooldownUntil, model.roaming, !model.hidden else { sweepHits = []; return }
        if model.whipNeedsOption && !option { sweepHits = []; return }
        let frames = critters.frames()
        for (id, f) in frames where !sweepHits.contains(id) {
            if segmentHits(a, b, f.insetBy(dx: -8, dy: -8)) { sweepHits.append(id) }
        }
        guard sweepHits.count >= 2, let first = sweepTrail.first else { return }
        let dist = zip(sweepTrail, sweepTrail.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.p.x - $1.0.p.x, $1.1.p.y - $1.0.p.y) }
        let speed = dist / CGFloat(max(t - first.t, 0.05))
        if speed >= Self.sweepSpeed {
            let ids = sweepHits
            sweepHits = []; sweepCooldownUntil = t + 1.5
            if FloatingPanel.debugMouse { NSLog("EOHANG sweep → %@ speed=%.0f", ids.joined(separator: ","), speed) }
            model.whipMany(ids)
        }
        // 느려지면 모은 것을 버린다 (지나가다 멈춘 건 휘두른 게 아니다)
        if speed < 200 { sweepHits = [] }
    }

    /// 선분 a→b 가 사각형을 지나는가 (양 끝이 안이거나, 변과 교차)
    private func segmentHits(_ a: NSPoint, _ b: NSPoint, _ r: NSRect) -> Bool {
        if r.contains(a) || r.contains(b) { return true }
        func cross(_ p: NSPoint, _ q: NSPoint, _ r1: NSPoint, _ r2: NSPoint) -> Bool {
            func d(_ u: NSPoint, _ v: NSPoint, _ w: NSPoint) -> CGFloat { (v.x - u.x) * (w.y - u.y) - (v.y - u.y) * (w.x - u.x) }
            return (d(p, q, r1) * d(p, q, r2) < 0) && (d(r1, r2, p) * d(r1, r2, q) < 0)
        }
        let c = [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.minX, y: r.maxY)]
        for i in 0..<4 where cross(a, b, c[i], c[(i + 1) % 4]) { return true }
        return false
    }

    // MARK: 바쁘면 숨기 — 마우스를 열심히 움직이거나 타자를 치면 돌아다니는 애들이 사라지고, 손을 놓으면 돌아온다
    // 키보드는 감시하지 않고 「마지막 키 입력이 몇 초 전인가」만 묻는다 (권한 불필요).

    static let dodgeMouseDistance: CGFloat = 1200   // 3초 안에 이만큼 움직이면 바쁨 (≈400px/s)
    static let dodgeAfter: TimeInterval = 2.5       // 바쁜 상태가 이만큼 이어지면 숨김
    static let returnAfter: TimeInterval = 8        // 조용한 상태가 이만큼 이어지면 복귀

    private func startBusyDetector() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.evaluateBusy() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        busyTimer = t
    }

    private func evaluateBusy() {
        let now = ProcessInfo.processInfo.systemUptime
        mouseTrail.removeAll { now - $0.t > 3 }
        let m = model
        // 숨길 상황이 아니면 (설정 꺼짐·창 보기·당근밭·이미 숨김) 바로 복귀
        guard m.autoDodge, m.roaming, !m.hidden, !m.caged else { critters.setDodged(false); busySince = nil; quietSince = nil; return }
        if m.hoverWhipID != nil || NSApp.isActive {                   // 채찍질·우리 앱을 쓰는 중엔 판단 보류
            busySince = nil; return
        }
        let dist = mouseTrail.reduce(0) { $0 + $1.d }
        let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let scrollIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
        let busy = dist > Self.dodgeMouseDistance || keyIdle < 1.5 || scrollIdle < 1.5
        if busy { busySince = busySince ?? now; quietSince = nil }
        else { quietSince = quietSince ?? now; busySince = nil }
        if FloatingPanel.debugMouse { NSLog("EOHANG busy dist=%.0f key=%.1f scroll=%.1f busy=%d dodged=%d", dist, keyIdle, scrollIdle, busy ? 1 : 0, critters.dodged ? 1 : 0) }
        if !critters.dodged, let b = busySince, now - b >= Self.dodgeAfter { critters.setDodged(true) }
        if critters.dodged, let q = quietSince, now - q >= Self.returnAfter { critters.setDodged(false) }
    }

    /// 커서를 따라다니는 작은 채찍 (채찍 맞을 캐릭터 위에서만)
    private func moveFollower(to p: NSPoint) {
        if cursorFollower == nil {
            let size = NSSize(width: 48, height: 48)        // 포인터 옆에 크게 — 시스템 커서가 안 바뀌어도 눈에 띄게
            let w = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            w.isFloatingPanel = true
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: WhipGlyph(size: 48))   // 앱 아이콘의 채찍
            host.sizingOptions = []
            w.contentView = host
            cursorFollower = w
        }
        guard let w = cursorFollower else { return }
        w.setFrameOrigin(NSPoint(x: p.x + 10, y: p.y - 40))
        if !w.isVisible { w.orderFrontRegardless() }
    }

    private func applyTheme(_ th: Theme) {
        panel.appearance = NSAppearance(named: th.dark ? .darkAqua : .aqua)
        effectView.material = th.material
        solidView.layer?.backgroundColor = th.solid?.cgColor
        solidView.isHidden = th.solid == nil
        solidView.layer?.cornerRadius = 14
        model.objectWillChange.send()
    }

    // MARK: 메뉴 막대 채찍

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 앱 아이콘과 같은 채찍, 템플릿 이미지 (메뉴 막대 밝기에 맞춰 검정/흰으로). 18pt 에 맞춰 2배로 그린다
        let img = WhipArt.templateImage(size: 36)
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        item.button?.image = img
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = t("Whiplash — click for menu")
        // 노치 맥북: 새 항목은 맨 왼쪽(노치 뒤)에 들어가 안 보일 수 있다. 처음 한 번은 오른쪽 가까이(오른쪽 끝에서 300pt) 자리를 잡아 준다.
        // 사용자가 ⌘-끌어서 옮기면 그 자리가 기억된다.
        if UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position WhiplashStatus") == nil {
            UserDefaults.standard.set(300, forKey: "NSStatusItem Preferred Position WhiplashStatus")
        }
        item.autosaveName = "WhiplashStatus"
        item.isVisible = true
        item.behavior = []                           // 끌어서 빼지 못하게 (실수로 사라지는 것 방지)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        if ProcessInfo.processInfo.environment["WHIPLASH_DEBUG_STATUS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSLog("EOHANG status visible=%d length=%.0f window=%@ screen=%@ image=%@",
                      item.isVisible ? 1 : 0, item.length,
                      item.button?.window.map { NSStringFromRect($0.frame) } ?? "nil",
                      item.button?.window?.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                      item.button?.image.map { NSStringFromSize($0.size) } ?? "nil")
            }
        }
    }

    /// Dock 아이콘을 켜면 앱이 활성화될 수 있으니 ⌘Q·⌘H 가 되는 최소 메뉴
    private func makeMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Whiplash")
        appMenu.addItem(withTitle: t("Show Whiplash window"), action: #selector(showPanelAction), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("Hide Whiplash"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: t("Quit Whiplash"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    /// Dock 아이콘·메뉴의 「채찍질 창 보이기」: 리스트 모드로 전환 (돌아다니기는 끈다)
    @objc private func showPanelAction() {
        model.hidden = false
        model.roaming = false
    }

    /// Dock 아이콘을 누르면 창을 다시 보인다
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanelAction()
        return false
    }

    /// Dock 아이콘 오른쪽 클릭 메뉴
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu
    }

    private func menuItem(_ title: String, on: Bool? = nil, key: HotAction? = nil,
                          _ handler: @escaping () -> Void) -> NSMenuItem {
        let i = ActionItem(title: title, action: #selector(ActionItem.run(_:)), keyEquivalent: "")
        i.target = i
        i.handler = handler
        if let on = on { i.state = on ? .on : .off }
        if let key = key, let c = hotKeys.combos[key] {      // 표시만. 실제로는 전역 단축키가 먹는다
            i.keyEquivalent = c.keyEquivalent
            i.keyEquivalentModifierMask = c.cocoaModifiers
        }
        return i
    }

    // MARK: 전역 단축키

    private func reloadHotKeys() {
        let m = model
        let bad = hotKeys.reload(actions: [
            .hide:   { m.hidden.toggle() },
            .roam:   { m.roaming.toggle(); if m.roaming { m.hidden = false } },
            .small:  { if m.roaming { m.critterSmall.toggle() } else { m.compact.toggle() } },
            .cage:   { m.caged.toggle(); if m.caged { m.roaming = true; m.hidden = false } },
            .whip:   { m.whipRandom() },
            .whipAll: { m.whipAll() },
            .treatAll: { m.treatAll() },
            .megaphone: { [weak self] in self?.openMegaphone() },
            .gather: { [weak self] in m.hidden = false; m.roaming = true; self?.critters.gatherToMouse() },
            .panel:  { m.hidden = false; m.panelWithCritters.toggle() },        // 둘 다 보기 켜고 끄기
        ])
        NSLog("Whiplash 단축키 \(hotKeys.combos.count)개 등록")
        if !bad.isEmpty {
            NSLog("Whiplash 단축키 못 읽음: \(bad)")
            NSSound(named: "Basso")?.play()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let m = model
        let s = m.snapshot
        let working = s.groups.filter { $0.awake }.count
        let waiting = s.groups.filter { $0.session?.needsYou == true }.count
        reloadHotKeysIfChanged()
        menu.removeAllItems()
        let head = NSMenuItem(title: s.groups.isEmpty ? t("No agents running right now")
                                                       : tf("%d critters · %d working · %d need you", s.groups.count, working, waiting),
                              action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        if m.quotaEnabled, let quota = m.quota {
            let q = NSMenuItem(title: quota.summary, action: nil, keyEquivalent: "")
            q.isEnabled = false
            menu.addItem(q)
        }
        menu.addItem(.separator())
        // 보기: 셋 중 하나
        menu.addItem(menuItem(t("Let loose — roam the screen"), on: m.roaming && !m.hidden, key: .roam) { m.roaming = true; m.hidden = false })
        menu.addItem(menuItem(t("Show as window"), on: !m.roaming && !m.hidden) { m.roaming = false; m.hidden = false })
        menu.addItem(menuItem(t("Hide all"), on: m.hidden, key: .hide) { m.hidden = true })
        menu.addItem(.separator())
        // 동작
        menu.addItem(menuItem(t("Come here — gather at the cursor"), key: .gather) { [weak self] in m.hidden = false; m.roaming = true; self?.critters.gatherToMouse() })
        menu.addItem(menuItem(t("Plant in the carrot field"), on: m.caged, key: .cage) { m.caged.toggle(); if m.caged { m.roaming = true; m.hidden = false } })
        menu.addItem(menuItem(t("Whip any idle one"), key: .whip) { m.whipRandom() })
        menu.addItem(menuItem(t("Whip everyone idle"), key: .whipAll) { m.whipAll() })
        menu.addItem(menuItem(t("Treat everyone working 🥕"), key: .treatAll) { m.treatAll() })
        if !Paths.sandboxed { menu.addItem(menuItem(t("Megaphone — same message to everyone…"), key: .megaphone) { [weak self] in self?.openMegaphone() }) }
        if !Paths.sandboxed {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            menu.addItem(submenu(m.autoWhipOn ? tf("Auto-whip ⚡ until %@", f.string(from: m.autoWhipUntil!)) : t("Auto-whip"), autoWhipMenu()))
        }
        menu.addItem(.separator())
        menu.addItem(submenu("Settings", settingsMenu()))
        menu.addItem(.separator())
        menu.addItem(menuItem(t("Quit Whiplash")) { NSApp.terminate(nil) })
    }

    private func autoWhipMenu() -> NSMenu {
        let m = model
        let auto = NSMenu()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let autoHead = NSMenuItem(title: m.autoWhipOn ? tf("On — until %@ · every %d min · %d whips", f.string(from: m.autoWhipUntil!), Int(m.autoWhipInterval / 60), m.autoWhipCount)
                                                  : t("Off"), action: nil, keyEquivalent: "")
        autoHead.isEnabled = false
        auto.addItem(autoHead)
        auto.addItem(.separator())
        func until(_ title: String, _ date: @escaping () -> Date) -> NSMenuItem { menuItem(title) { m.setAutoWhip(until: date()) } }
        func next(_ hour: Int) -> Date { Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600) }
        auto.addItem(until(t("For 1 hour")) { Date().addingTimeInterval(3600) })
        auto.addItem(until(t("For 3 hours")) { Date().addingTimeInterval(3 * 3600) })
        auto.addItem(until(t("Until 6 PM")) { next(18) })
        auto.addItem(until(t("Until midnight")) { next(0) })
        auto.addItem(until(t("Until 9 AM")) { next(9) })
        if m.autoWhipOn { auto.addItem(menuItem(t("Turn off")) { m.setAutoWhip(until: nil) }) }
        auto.addItem(.separator())
        let every = NSMenu()
        for mins in [3, 5, 10, 20, 30, 60] {
            every.addItem(menuItem(tf("Every %d min", mins), on: Int(m.autoWhipInterval / 60) == mins) { m.autoWhipInterval = TimeInterval(mins * 60) })
        }
        auto.addItem(submenu(tf("Interval — every %d min", Int(m.autoWhipInterval / 60)), every))
        auto.addItem(menuItem(t("Edit whip prompt…")) { m.editWhipWords() })
        return auto
    }

    /// 「설정」 하위 메뉴 — 메뉴 막대·Dock·오른쪽 클릭에서 같이 쓴다
    private func settingsMenu() -> NSMenu {
        let m = model
        let menu = NSMenu()
        // Language 는 어느 언어에서나 맨 위, 영어 표기 (만국공통)
        let langMenu = NSMenu()
        for l in Lang.allCases {
            langMenu.addItem(menuItem(l.title, on: Lang.current == l) { Lang.current = l; m.objectWillChange.send() })
        }
        menu.addItem(submenu("Language", langMenu))
        menu.addItem(.separator())
        // 풀어놓기
        menu.addItem(menuItem(t("Roam small (no name tags)"), on: m.critterSmall, key: .small) { m.critterSmall.toggle() })
        menu.addItem(menuItem(t("Water tile behind critters"), on: m.critterBox) { m.critterBox.toggle() })
        menu.addItem(menuItem(t("Show list while roaming (both at once)"), on: m.panelWithCritters, key: .panel) { m.panelWithCritters.toggle() })
        menu.addItem(menuItem(t("Hide while I'm busy (fast mouse or typing)"), on: m.autoDodge) { m.autoDodge.toggle() })
        menu.addItem(.separator())
        // 채찍질 창
        menu.addItem(menuItem(t("Compact view"), on: m.compact) { m.compact.toggle() })
        menu.addItem(menuItem(t("Always on top"), on: m.alwaysOnTop) { m.alwaysOnTop.toggle() })
        menu.addItem(.separator())
        // 채찍
        menu.addItem(menuItem(t("Whip only while holding ⌥ (avoid accidents)"), on: m.whipNeedsOption) { m.whipNeedsOption.toggle() })
        let body = NSMenu()
        func line(_ text: String) { if !text.isEmpty { let i = NSMenuItem(title: "   " + text, action: nil, keyEquivalent: ""); i.isEnabled = false; body.addItem(i) } }
        // 꺼져 있으면 "어떻게 하는 건지" 한 줄, 켜져 있으면 상태 한 줄
        body.addItem(menuItem(t("AirPods head flick — whip everyone idle"), on: m.headFlickOn) { m.headFlickOn.toggle() })
        if #available(macOS 14.0, *), let hf = headFlick as? HeadFlick {
            line(m.headFlickOn ? hf.status : t("Wearing AirPods Pro / 3rd gen / Max, snap your head sideways"))
        } else { line(t("Needs macOS 14 or later")) }
        body.addItem(menuItem(t("Camera hand swing — whip everyone idle"), on: m.handCamOn) { m.handCamOn.toggle() })
        line(m.handCamOn ? handSwing.status : t("Swing a hand sideways in front of the camera, arm's length away"))
        body.addItem(menuItem(t("Say \"whoosh-crack!\" — microphone"), on: m.mouthOn) { m.mouthOn.toggle() })
        line(m.mouthOn ? mouth.status : t("A short sharp burst after a quiet moment; talking doesn't count"))
        body.addItem(menuItem(t("Accept iPhone / iPad / Apple Watch remote"), on: m.remoteOn) { m.remoteOn.toggle() })
        line(m.remoteOn ? remote.status : t("Whiplash Remote app on the same Wi‑Fi: flick the phone, snap the wrist, or tap"))
        body.addItem(.separator())
        let hint = NSMenuItem(title: t("Sensors, camera, microphone and network are used only while on. Nothing is recorded."), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        body.addItem(hint)
        menu.addItem(submenu(t("Whip with your body"), body))
        if Paths.sandboxed {
            menu.addItem(menuItem(Paths.hasHomeAccess ? t("Re-pick home folder access…") : t("Allow home folder access… (to see sessions)")) { Paths.requestHomeAccess() })
        } else {
            menu.addItem(menuItem(t("Show remaining quota 🥕 (reads Claude login from Keychain)"), on: m.quotaEnabled) { m.quotaEnabled.toggle() })
            menu.addItem(menuItem(t("Edit whip prompt…")) { m.editWhipWords() })       // 채찍질 때 세션에 보내는 글
            menu.addItem(menuItem(t("Edit treat prompt…")) { m.editTreatWords() })      // 칭찬할 때 보내는 글
            let tasks = NSMenu()
            tasks.addItem(menuItem(t("Edit task list…")) { m.editTasks() })
            tasks.addItem(menuItem(t("Open results folder")) { m.openResults() })
            menu.addItem(submenu(t("Helper agent tasks (for agents that can't receive messages)"), tasks))
        }
        menu.addItem(.separator())
        // 모양·언어·단축키
        let themeMenu = NSMenu()
        for th in Theme.all { themeMenu.addItem(menuItem(t(th.title), on: m.theme == th.id) { m.theme = th.id }) }
        menu.addItem(submenu(t("Theme"), themeMenu))
        menu.addItem(menuItem(t("Edit hotkeys…")) { _ = HotKeys.loadCombos(); NSWorkspace.shared.open(HotKeys.file) })
        menu.addItem(.separator())
        menu.addItem(menuItem(t("Demo critters (fake agents, nothing is sent)"), on: m.demo) { m.demo.toggle() })
        menu.addItem(menuItem(t("Show icon in Dock"), on: m.dockIcon) { m.dockIcon.toggle() })
        menu.addItem(menuItem(t("Open at login"), on: m.loginItemEnabled) { m.loginItemEnabled.toggle() })
        return menu
    }

    /// hotkeys.json 이 바뀌었으면 다시 등록 (메뉴를 열 때마다 확인 — 「다시 읽기」 항목 대신)
    private var hotKeysStamp: Date?

    // MARK: 몸으로 때리기 — 에어팟·카메라·리모트. 설정이 켜진 동안만 돈다.
    private var headFlick: Any? = { if #available(macOS 14.0, *) { return HeadFlick() } else { return nil } }()
    private let handSwing = HandSwing()
    private let remote = RemoteReceiver()
    private let mouth = MouthWhip()

    private func installBodyWhips() {
        let m = model
        if #available(macOS 14.0, *), let hf = headFlick as? HeadFlick {
            hf.onFlick = { [weak self] speed in
                if FloatingPanel.debugMouse { NSLog("EOHANG head flick %.1f rad/s", speed) }
                self?.bodyWhip()
            }
        }
        handSwing.onSwing = { [weak self] dx in
            if FloatingPanel.debugMouse { NSLog("EOHANG hand swing %.2f", dx) }
            self?.bodyWhip()
        }
        remote.onCommand = { [weak self] cmd, strength in
            if FloatingPanel.debugMouse { NSLog("EOHANG remote %@ %.1f", cmd, strength) }
            switch cmd {
            case "whip": m.whipRandom()
            default: self?.bodyWhip()
            }
        }
        mouth.onCrack = { [weak self] db in
            if FloatingPanel.debugMouse { NSLog("EOHANG mouth crack %.0f dB", db) }
            self?.bodyWhip()
        }
        m.onBodyWhipChange = { [weak self] in self?.syncBodyWhips() }
        syncBodyWhips()
    }

    /// 몸으로 때리면 쉬는 애 전부. 숨겨 뒀으면 잠깐 보여 준다.
    private func bodyWhip() {
        if model.hidden { model.hidden = false }
        critters.setDodged(false)
        model.whipAll()
    }

    private func syncBodyWhips() {
        if #available(macOS 14.0, *), let hf = headFlick as? HeadFlick { model.headFlickOn ? hf.start() : hf.stop() }
        model.handCamOn ? handSwing.start() : handSwing.stop()
        model.remoteOn ? remote.start() : remote.stop()
        model.mouthOn ? mouth.start() : mouth.stop()
    }
    private func reloadHotKeysIfChanged() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: HotKeys.file.path))?[.modificationDate] as? Date
        guard stamp != hotKeysStamp else { return }
        hotKeysStamp = stamp
        reloadHotKeys()
    }

    /// 위쪽 모서리를 고정한 채 내용 크기에 맞춘다
    private func fit(_ size: CGSize) {
        guard let panel = panel, size.width > 1, size.height > 1 else { return }
        var f = panel.frame
        let w = size.width.rounded(.up), h = size.height.rounded(.up)
        guard abs(f.width - w) > 0.5 || abs(f.height - h) > 0.5 else { return }
        let top = f.maxY
        f.size = NSSize(width: w, height: h)
        f.origin.y = top - h
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
    }

    private static func roundedMask(radius r: CGFloat) -> NSImage {
        let edge = 2 * r + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}
