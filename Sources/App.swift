import AppKit
import SwiftUI
import Combine

@main
@MainActor
enum EohangApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)      // 시작은 조용히. Dock 아이콘은 설정(dockIcon)에 따라 켠다
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// 테두리 없는 작은 창. 왼쪽 클릭으로 끌어서 옮기고, 두 번 클릭하면 작게/크게.
/// 버튼 자리(noDragRects, 창 왼쪽 위 기준)는 클릭을 그대로 버튼에 넘긴다.
/// 쉬는 캐릭터 자리(whipTargets) 위에서 마우스를 빠르게 왕복하면 채찍질.
final class FloatingPanel: NSPanel {
    var onDoubleClick: (() -> Void)?
    var onSwing: ((String) -> Void)?
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

    static let debugMouse = ProcessInfo.processInfo.environment["EOHANG_DEBUG_MOUSE"] != nil

    /// 전역 마우스 모니터가 화면 좌표로 넣어 준다 (키 창이 아니어도 받게)
    func trackSwing(screen p: NSPoint, time t: TimeInterval) {
        guard isVisible, frame.insetBy(dx: -30, dy: -30).contains(p) else { lastMove = nil; enteredAt = [:]; return }
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

    /// 채찍질 = 캐릭터 위에 0.35초 머문 뒤(채찍 커서가 뜬 뒤), 가운데 선을 1초 안에 세 번 빠르게(초당 400px 이상) 가로지르기.
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
        guard speed >= 400 else { return }

        for (id, r) in whipTargets {
            let band = r.insetBy(dx: -4, dy: -14)
            let midY = (p.y + last.p.y) / 2
            let a = last.p.x - r.midX, b = p.x - r.midX
            guard midY >= band.minY, midY <= band.maxY,
                  (a < 0 && b >= 0) || (a > 0 && b <= 0) else { continue }     // 가운데 선에 딱 걸친 샘플도 가로지른 것
            guard let entered = enteredAt[id], t - entered >= 0.35 else {
                if Self.debugMouse { NSLog("EOHANG cross %@ rejected: dwell %.2f", id, enteredAt[id].map { t - $0 } ?? -1) }
                continue
            }
            var list = (passes[id] ?? []).filter { t - $0 < 1.0 }
            list.append(t)
            if Self.debugMouse { NSLog("EOHANG cross %@ ok passes=%d", id, list.count) }
            if list.count >= 3, t - (lastSwing[id] ?? 0) > 2 {
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
    private var host: NSHostingView<WidgetView>!
    private let model = Model()
    private var critters: CritterManager!
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()
    private var mouseMonitors: [Any] = []
    private var whipCursorShown = false
    private var cursorFollower: NSPanel?
    private var prompt: PromptPanel?
    private var occlusionObserver: NSObjectProtocol?
    private var modelSub: AnyCancellable?
    private var refitPending = false

    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    private static let autosaveName = "EohangPanel"

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

        var root = WidgetView(model: model)
        root.onNoDrag = { [weak panel] rects in panel?.noDragRects = rects }
        root.onWhipTargets = { [weak panel] rects in panel?.whipTargets = rects }
        root.onClickTargets = { [weak panel] rects in panel?.clickTargets = rects }
        panel.onSwing = { [weak self] id in self?.model.whip(id: id) }
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
        if let text = ProcessInfo.processInfo.environment["EOHANG_SEND_TEST"] {      // 개발용: 6초 뒤 첫 세션에 보내 본다
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.session != nil }) else { NSLog("EOHANG send-test: 세션 없음"); return }
                self.model.send(text, to: g) { r in NSLog("EOHANG send-test %@ → %@", g.id, String(describing: r)) }
            }
        }
        makeStatusItem()
        makeMainMenu()
        reloadHotKeys()
        installMouseMonitor()
        model.onDockIconChange = { on in NSApp.setActivationPolicy(on ? .regular : .accessory) }
        if model.dockIcon { NSApp.setActivationPolicy(.regular) }
        if Paths.sandboxed && !Paths.hasHomeAccess && ProcessInfo.processInfo.environment["EOHANG_NO_PROMPT"] == nil {
            Paths.requestHomeAccess()
        }
        NSLog("Whiplash sandboxed=%d homeAccess=%d home=%@", Paths.sandboxed ? 1 : 0, Paths.hasHomeAccess ? 1 : 0, Paths.home)
        if ProcessInfo.processInfo.environment["EOHANG_DEBUG_PROC"] != nil { ProcessProbe.log() }
        if ProcessInfo.processInfo.environment["EOHANG_DEBUG_SOCK"] != nil {      // 개발용: 세션 소켓에 connect 만 (아무것도 안 보냄)
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
        model.onLevelChange = { [weak self] onTop in
            guard let self = self else { return }
            self.panel?.level = self.level
            self.critters.sync(level: self.level)
        }
        // 내용이 바뀔 때마다 (한 번에 묶어서) 창 크기를 내용에 맞추고 크리터 창 목록을 맞춘다
        modelSub = model.objectWillChange.sink { [weak self] _ in self?.scheduleRefit() }
        model.start()
        scheduleRefit()

        // 개발용: EOHANG_SNAPSHOT=/경로.png 로 띄우면 5초 뒤 화면을 그 파일로 저장
        if ProcessInfo.processInfo.environment["EOHANG_SWING_TEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.swingTest() }
        }
        if ProcessInfo.processInfo.environment["EOHANG_PROMPT_TEST"] != nil {        // 개발용: 4초 뒤 첫 세션 입력창 열기
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.session != nil }) else { return }
                self.openPrompt(for: g.id, near: NSPoint(x: 600, y: 500))
            }
        }
        if ProcessInfo.processInfo.environment["EOHANG_ANGRY_TEST"] != nil {        // 개발용: 내 차례인 세션을 두 번 때려 화내는 모습
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self = self, let g = self.model.snapshot.groups.first(where: { $0.session?.needsYou == true }) else { NSLog("EOHANG angry-test: 대상 없음"); return }
                self.model.whip(g); self.model.whip(g)
            }
        }
        if let path = ProcessInfo.processInfo.environment["EOHANG_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.saveSnapshot(to: path) }
        }
    }

    /// 개발용: EOHANG_SWING_TEST=1 이면 6초 뒤 첫 쉬는 캐릭터 위로 가짜 마우스 이벤트를 보내 감지만 확인 (채찍은 안 때림)
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
        save(critters.cageContentView, (path as NSString).deletingPathExtension + "-cage.png")
        save(prompt?.contentView, (path as NSString).deletingPathExtension + "-prompt.png")
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

    /// 풀어놓았고 크리터가 하나라도 있으면 어항 창은 숨긴다. 「모두 숨기기」면 전부 숨긴다.
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
                menu.addItem(menuItem(t("Claude 앱 열기")) { m.wakeClaude(dir: nil) })
                let term = NSMenu()
                for d in m.recentProjects() { term.addItem(menuItem((d as NSString).lastPathComponent) { m.wakeClaude(dir: d) }) }
                term.addItem(.separator())
                term.addItem(menuItem(t("홈 폴더에서")) { m.wakeClaude(dir: Paths.home) })
                let termItem = NSMenuItem(title: t("터미널에서 claude 열기"), action: nil, keyEquivalent: "")
                termItem.submenu = term
                menu.addItem(termItem)
                menu.addItem(.separator())
            }
            if m.canWhip(g), !g.id.hasPrefix("app:"), g.id != Model.ghostID, !Paths.sandboxed {
                let tasks = NSMenu()
                for task in m.tasks { tasks.addItem(menuItem(task.title) { m.whip(g, task: task) }) }
                let tasksItem = NSMenuItem(title: t("채찍 — 일감 골라 시키기"), action: nil, keyEquivalent: "")
                tasksItem.submenu = tasks
                menu.addItem(tasksItem)
                menu.addItem(.separator())
            }
            if let s = g.session {
                let head = NSMenuItem(title: s.name.isEmpty ? g.label : s.name, action: nil, keyEquivalent: "")
                head.isEnabled = false
                menu.addItem(head)
                menu.addItem(menuItem(m.isImmune(g) ? t("채찍 면역 풀기") : t("채찍 면역 (손·오토 채찍 다 안 맞음)"), on: m.isImmune(g)) { m.toggleImmune(g) })
                if Paths.sandboxed {
                    menu.addItem(menuItem(t("전체 기능판 받기… (채찍 메시지·지시 보내기·오토 채찍)")) { Paths.openFullEdition() })
                } else {
                    let hint = NSMenuItem(title: t("제자리 클릭 → 지시 보내기"), action: nil, keyEquivalent: "")
                    hint.isEnabled = false
                    menu.addItem(hint)
                }
                menu.addItem(menuItem(t("창 앞으로")) { m.bringToFront(g) })
                menu.addItem(menuItem(t("폴더 열기")) { m.openFolder(g) })
                if !s.lastPrompt.isEmpty { menu.addItem(menuItem(t("마지막 지시 복사")) { m.copyPrompt(g) }) }
                if s.transcript != nil { menu.addItem(menuItem(t("대화 기록 파일 열기")) { m.openTranscript(g) }) }
                if s.status == .busy && !s.isDesktop && !Paths.sandboxed {
                    menu.addItem(.separator())
                    menu.addItem(menuItem(t("하던 일 멈추기 (Ctrl-C)")) { m.interrupt(g) })
                }
            } else if g.id != Model.ghostID {
                menu.addItem(menuItem(t("창 앞으로")) { m.bringToFront(g) })
                if g.dir != nil { menu.addItem(menuItem(t("폴더 열기")) { m.openFolder(g) }) }
            }
            menu.addItem(.separator())
        }
        if m.roaming {
            menu.addItem(menuItem(m.caged ? t("우리 풀어주기") : t("우리에 가두기"), key: .cage) { m.caged.toggle() })
            menu.addItem(menuItem(t("채찍질 창으로 모으기"), key: .roam) { m.roaming = false })
            menu.addItem(menuItem(m.critterSmall ? t("크게 풀어놓기") : t("작게 풀어놓기"), key: .small) { m.critterSmall.toggle() })
        } else {
            menu.addItem(menuItem(t("풀어놓기 — 화면 돌아다니기"), key: .roam) { m.roaming = true; m.hidden = false })
        }
        menu.addItem(menuItem(t("모두 숨기기"), key: .hide) { m.hidden = true })
        menu.addItem(.separator())
        let settings = NSMenu()
        menuNeedsUpdate(settings)
        let settingsItem = NSMenuItem(title: t("채찍질 설정"), action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        menu.addItem(settingsItem)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    // MARK: 지시 입력창

    /// 캐릭터를 제자리 클릭하면 그 위에 작은 입력창. 엔터로 보내고 esc 로 닫는다.
    func openPrompt(for id: String, near p: NSPoint) {
        guard model.snapshot.groups.first(where: { $0.id == id })?.session != nil else {
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
    }

    private func mouseMoved(_ e: NSEvent) {
        let p = NSEvent.mouseLocation
        let t = ProcessInfo.processInfo.systemUptime      // 이벤트 시각 대신 (가짜 이벤트는 0일 수 있다)
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
        if over { moveFollower(to: p) }
        if over != whipCursorShown {
            whipCursorShown = over
            if over { WhipCursor.cursor.set() } else { NSCursor.arrow.set(); cursorFollower?.orderOut(nil) }
        }
    }

    /// 커서를 따라다니는 작은 채찍 (채찍 맞을 캐릭터 위에서만)
    private func moveFollower(to p: NSPoint) {
        if cursorFollower == nil {
            let size = NSSize(width: 26, height: 20)
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
            let host = NSHostingView(rootView: WhipCanvas(cell: 3).frame(width: size.width, height: size.height, alignment: .bottomLeading))
            host.sizingOptions = []
            w.contentView = host
            cursorFollower = w
        }
        guard let w = cursorFollower else { return }
        w.setFrameOrigin(NSPoint(x: p.x + 10, y: p.y - 22))
        if !w.isVisible { w.orderFrontRegardless() }
    }

    // MARK: 메뉴 막대 채찍

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 꽃게 + 채찍, 템플릿 이미지 (메뉴 막대 밝기에 맞춰 검정/흰으로)
        let rows = [
            "KK........KK....AA",
            "KAK......KAK...A..",
            "KAAK....KAAK..A...",
            ".KAK....KAK..A....",
            "..KKKKKKKK..H.....",
            ".KBLBBBBBBK.H.....",
            "KBBEBBBBEBBK......",
            "KBCBBKKBBCBK......",
            ".KKKKKKKKKK.......",
            ".K.K....K.K.......",
        ]
        let img = pixelImage(rows: rows, cell: 1.6) { ch in ch == "." || ch == "L" || ch == "C" ? nil : Color.black }
        img.isTemplate = true
        item.button?.image = img
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = t("Whiplash — 누르면 메뉴")
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
        if ProcessInfo.processInfo.environment["EOHANG_DEBUG_STATUS"] != nil {
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
        appMenu.addItem(withTitle: t("채찍질 창 보이기"), action: #selector(showPanelAction), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("Whiplash 숨기기"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: t("Whiplash 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        menu.removeAllItems()
        let head = NSMenuItem(title: s.groups.isEmpty ? t("지금 돌아가는 에이전트가 없어요")
                                                       : tf("%d마리 · %d 일하는 중 · %d 내 차례", s.groups.count, working, waiting),
                              action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        if m.quotaEnabled, let five = m.quota?.fiveHour {
            let q = NSMenuItem(title: five.utilization >= 100 ? t("🥕 당근밭 다 뽑힘 · 파업!") : tf("🥕 당근밭 %d%% 남음 · %@", Int(five.remaining), five.resetsAt.map { fmtAgoFuture($0) } ?? ""),
                               action: nil, keyEquivalent: "")
            q.isEnabled = false
            menu.addItem(q)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(t("모두 숨기기"), on: m.hidden, key: .hide) { m.hidden.toggle() })
        menu.addItem(menuItem(t("풀어놓기 — 화면 돌아다니기"), on: m.roaming, key: .roam) { m.roaming.toggle(); if m.roaming { m.hidden = false } })
        menu.addItem(menuItem(t("작게 풀어놓기 (이름표 없이)"), on: m.critterSmall, key: .small) { m.critterSmall.toggle() })
        menu.addItem(menuItem(t("우리에 가두기"), on: m.caged, key: .cage) { m.caged.toggle(); if m.caged { m.roaming = true; m.hidden = false } })
        menu.addItem(menuItem(t("이리 와 — 커서 자리로 모이기"), key: .gather) { [weak self] in m.hidden = false; m.roaming = true; self?.critters.gatherToMouse() })
        menu.addItem(menuItem(t("쉬는 애 아무나 채찍"), key: .whip) { m.whipRandom() })
        let auto = NSMenu()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let autoHead = NSMenuItem(title: m.autoWhipOn ? tf("켜짐 — %@ 까지 · %d분마다 · %d번 때림", f.string(from: m.autoWhipUntil!), Int(m.autoWhipInterval / 60), m.autoWhipCount)
                                                  : t("꺼짐"), action: nil, keyEquivalent: "")
        autoHead.isEnabled = false
        auto.addItem(autoHead)
        auto.addItem(.separator())
        func until(_ title: String, _ date: @escaping () -> Date) -> NSMenuItem { menuItem(title) { m.setAutoWhip(until: date()) } }
        func next(_ hour: Int) -> Date { Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600) }
        auto.addItem(until(t("1시간 동안")) { Date().addingTimeInterval(3600) })
        auto.addItem(until(t("3시간 동안")) { Date().addingTimeInterval(3 * 3600) })
        auto.addItem(until(t("퇴근(18시)까지")) { next(18) })
        auto.addItem(until(t("자정까지")) { next(0) })
        auto.addItem(until(t("아침 9시까지")) { next(9) })
        if m.autoWhipOn { auto.addItem(menuItem(t("끄기")) { m.setAutoWhip(until: nil) }) }
        auto.addItem(.separator())
        for mins in [3, 5, 10, 20, 30, 60] {
            auto.addItem(menuItem(tf("%d분마다", mins), on: Int(m.autoWhipInterval / 60) == mins) { m.autoWhipInterval = TimeInterval(mins * 60) })
        }
        auto.addItem(.separator())
        auto.addItem(menuItem(t("채찍 문구 편집…")) { m.editWhipWords() })
        let autoItem = NSMenuItem(title: m.autoWhipOn ? tf("오토 채찍질 ⚡ %@ 까지", f.string(from: m.autoWhipUntil!)) : t("오토 채찍질"), action: nil, keyEquivalent: "")
        autoItem.submenu = auto
        if !Paths.sandboxed { menu.addItem(autoItem) }
        menu.addItem(menuItem(t("풀어놓을 때 채찍질 창도 보기"), on: m.panelWithCritters, key: .panel) { m.panelWithCritters.toggle() })
        menu.addItem(menuItem(t("Dock 에 아이콘 보이기"), on: m.dockIcon) { m.dockIcon.toggle() })
        let langMenu = NSMenu()
        for l in Lang.allCases {
            langMenu.addItem(menuItem(l.title, on: Lang.current == l) { Lang.current = l; m.objectWillChange.send() })
        }
        let langItem = NSMenuItem(title: t("언어"), action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)
        if !Paths.sandboxed {
            menu.addItem(menuItem(t("당근밭 보기 — 남은 쿼터 (Claude 로그인 키체인 읽기)"), on: m.quotaEnabled) { m.quotaEnabled.toggle() })
        }
        menu.addItem(menuItem(t("⌥ 누른 채로만 채찍 (오작동 방지)"), on: m.whipNeedsOption) { m.whipNeedsOption.toggle() })
        menu.addItem(menuItem(t("캐릭터 뒤 물빛 칸"), on: m.critterBox) { m.critterBox.toggle() })
        menu.addItem(.separator())
        menu.addItem(menuItem(t("채찍질 창으로 보기"), on: !m.roaming && !m.hidden) { m.roaming = false; m.hidden = false })
        menu.addItem(menuItem(t("작게 보기"), on: m.compact) { m.compact.toggle() })
        menu.addItem(menuItem(t("항상 맨 위에"), on: m.alwaysOnTop) { m.alwaysOnTop.toggle() })
        menu.addItem(menuItem(t("로그인할 때 열기"), on: m.loginItemEnabled) { m.loginItemEnabled.toggle() })
        menu.addItem(.separator())
        if Paths.sandboxed {
            menu.addItem(menuItem(Paths.hasHomeAccess ? t("홈 폴더 접근 다시 고르기…") : t("홈 폴더 접근 허용… (세션 정보 보기)")) { Paths.requestHomeAccess() })
        }
        if Paths.sandboxed {
            menu.addItem(menuItem(t("전체 기능판 받기… (채찍 메시지·지시 보내기·오토 채찍)")) { Paths.openFullEdition() })
        } else {
            menu.addItem(menuItem(t("채찍 일감 편집…")) { m.editTasks() })
            menu.addItem(menuItem(t("채찍 결과 폴더 열기")) { m.openResults() })
        }
        menu.addItem(menuItem(t("단축키 편집…")) { _ = HotKeys.loadCombos(); NSWorkspace.shared.open(HotKeys.file) })
        menu.addItem(menuItem(t("단축키 다시 읽기")) { [weak self] in self?.reloadHotKeys() })
        menu.addItem(.separator())
        menu.addItem(menuItem(t("Whiplash 닫기")) { NSApp.terminate(nil) })
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
