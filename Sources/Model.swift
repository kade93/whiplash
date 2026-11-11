import Foundation
import Combine
import ServiceManagement
import AppKit

/// 화면 상태. 측정은 백그라운드 큐에서, 화면 갱신은 메인에서.
final class Model: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var storage: [StorageItem] = []
    @Published private(set) var disk = DiskInfo()
    @Published private(set) var tick = 0

    // MARK: 알림 — 과부하 · 유출 감시 (「알리고 물어보기」 창에 한 줄씩)
    enum OverloadMode: String { case off, ask, auto }      // 아무것도 안 함 · 알리고 물어보기(수동) · 알리고 답 없으면 자동으로 멈춤
    struct AgentAlert: Identifiable, Equatable {
        enum Kind: Equatable { case overload, risk(title: String, detail: String) }
        let id: String            // "overload:<칸>" / "risk:<도구 호출 id>"
        let groupID: String
        let kind: Kind
        let raisedAt: Date
        var since: Date           // 과부하가 시작된 때
    }
    @Published private(set) var alerts: [AgentAlert] = []
    var onAlertsChanged: (() -> Void)?
    @Published var overloadMode: OverloadMode { didSet { UserDefaults.standard.set(overloadMode.rawValue, forKey: "overloadMode"); if overloadMode == .off { dropAlerts { $0.kind == .overload } } } }
    @Published var overloadAfter: TimeInterval { didSet { UserDefaults.standard.set(overloadAfter, forKey: "overloadAfter") } }   // 과부하가 이만큼 이어지면
    static let overloadCountdown: TimeInterval = 20        // 자동: 물어보고 이만큼 답이 없으면 멈춘다
    /// 유출 감시 (숨은 설정, 메뉴에 없다): defaults write com.kade.whiplash leakGuard off|alert|whip. 기본 whip = 알리고 경고 프롬프트도 보냄
    var leakGuard: String { UserDefaults.standard.string(forKey: "leakGuard") ?? "whip" }
    private var overloadSince: [String: Date] = [:]
    private var overloadLastHot: [String: Date] = [:]
    private var overloadSettled: Set<String> = []          // 그냥 두기·멈춤을 고른 애: 식을 때까지 다시 안 묻는다
    private var risksSeen: Set<String> = []
    private var alertTimer: Timer?
    private static let overloadTest = ProcessInfo.processInfo.environment["WHIPLASH_OVERLOAD_TEST"]

    /// 작게 보기에서 캐릭터 밑에 이름을 적을지 (아이콘만으로는 누가 누군지 모르니 기본 켜짐)
    @Published var compactNames: Bool { didSet { UserDefaults.standard.set(compactNames, forKey: "compactNames") } }
    @Published var hoverInfoID: String? = nil          // 커서가 올라간 칸 (작게 보기 아래 줄에 「누가 · 뭘 하는 중」)
    /// 작게 보기에서 한 줄에 몇 마리까지 (넘치면 다음 줄)
    @Published var compactPerRow: Int { didSet { UserDefaults.standard.set(compactPerRow, forKey: "compactPerRow") } }
    @Published var compact: Bool {
        didSet { UserDefaults.standard.set(compact, forKey: "compact") }
    }
    /// 풀어놓기: 캐릭터들이 각자 작은 창이 되어 화면을 돌아다닌다
    @Published var roaming: Bool {
        didSet { UserDefaults.standard.set(roaming, forKey: "roaming") }
    }
    /// 작게 풀어놓기: 이름표 없이 작은 캐릭터만
    @Published var critterSmall: Bool {
        didSet { UserDefaults.standard.set(critterSmall, forKey: "critterSmall") }
    }
    /// 우리에 가두기: 울타리 창 안에서만 돌아다닌다
    @Published var caged: Bool {
        didSet { UserDefaults.standard.set(caged, forKey: "caged") }
    }
    /// 모두 숨기기: 창도 캐릭터도 안 보임 (메뉴 막대 아이콘으로 되돌림)
    @Published var hidden: Bool {
        didSet { UserDefaults.standard.set(hidden, forKey: "hidden") }
    }
    /// 풀어놓은 동안에도 채찍질 창(CPU·메모리·저장공간)을 같이 보일지
    @Published var panelWithCritters: Bool {
        didSet { UserDefaults.standard.set(panelWithCritters, forKey: "panelWithCritters") }
    }
    /// Dock 에 아이콘을 보일지 (끄면 메뉴 막대 채찍만)
    @Published var dockIcon: Bool {
        didSet { UserDefaults.standard.set(dockIcon, forKey: "dockIcon"); onDockIconChange?(dockIcon) }
    }
    var onDockIconChange: ((Bool) -> Void)?
    /// 테마 id (Theme.all)
    @Published var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: "theme"); Theme.current = Theme.named(theme); onThemeChange?(Theme.current) }
    }
    var onThemeChange: ((Theme) -> Void)?
    /// 돌아다닐 때 캐릭터 뒤에 물빛 칸을 그릴지
    @Published var critterBox: Bool {
        didSet { UserDefaults.standard.set(critterBox, forKey: "critterBox") }
    }
    @Published var alwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
            onLevelChange?(alwaysOnTop)
        }
    }
    var onLevelChange: ((Bool) -> Void)?
    var onStrike: ((String) -> Void)?          // 채찍 맞은 칸 id (돌아다닐 때 창이 폴짝)

    /// 「후-췻!」 + 「아야」. Resources/whip1~3.wav (tools/sound.swift 로 합성). 연타할수록 1→2→3
    static func playWhip(_ variant: Int = 1) {
        let v = min(max(variant, 1), 3)
        if let url = Bundle.main.url(forResource: "whip\(v)", withExtension: "wav"), let s = NSSound(contentsOf: url, byReference: true) {
            s.volume = 0.9
            s.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }

    /// 트랙패드 「툭」. 여러 마리면 소리와 같은 간격으로 연타.
    static func haptic(_ n: Int = 1) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        for i in 0..<min(max(n, 1), 6) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.055) {
                performer.perform(i == 0 ? .levelChange : .generic, performanceTime: .now)
            }
        }
    }

    /// 여러 마리를 한 번에 때릴 때: 「짝」이 겹치고 「아야」가 돌림노래처럼 — 마릿수만큼 어긋나게 겹쳐 더 찰지게
    static func playWhipChorus(_ n: Int) {
        haptic(n)
        guard n > 1 else { playWhip(1); return }
        let voices = min(n, 6)
        for i in 0..<voices {
            let delay = Double(i) * 0.055 + Double.random(in: 0...0.02)
            let variant = i == 0 ? min(n, 3) : (i % 3) + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let url = Bundle.main.url(forResource: "whip\(variant)", withExtension: "wav"), let snd = NSSound(contentsOf: url, byReference: true) {
                    snd.volume = Float(max(0.45, 0.95 - Double(i) * 0.08))
                    snd.play()
                }
            }
        }
    }

    /// 8초 안에 연타하면 횟수가 올라간다 (소리·리액션이 달라짐)
    private var hitStreak: [String: (count: Int, at: Date)] = [:]
    func hit(_ id: String) -> Int {
        let now = Date()
        let n = (hitStreak[id].map { now.timeIntervalSince($0.at) < 8 ? $0.count + 1 : 1 }) ?? 1
        hitStreak[id] = (n, now)
        return n
    }

    /// 데모: 가짜 에이전트들 (Claude 없이도 캐릭터를 본다 — 심사·스크린샷용). 메시지는 보내지 않고 반응만.
    @Published var demo: Bool { didSet { UserDefaults.standard.set(demo, forKey: "demo"); snapshot = merged(snapshot) } }

    /// 몸으로 때리기: 에어팟 고개 휙 · 카메라 손 휘두르기 · 아이폰/워치 리모트 (켤 때만 센서·카메라·네트워크를 연다)
    @Published var headFlickOn: Bool { didSet { UserDefaults.standard.set(headFlickOn, forKey: "headFlickOn"); onBodyWhipChange?() } }
    @Published var handCamOn: Bool { didSet { UserDefaults.standard.set(handCamOn, forKey: "handCamOn"); onBodyWhipChange?() } }
    @Published var remoteOn: Bool { didSet { UserDefaults.standard.set(remoteOn, forKey: "remoteOn"); onBodyWhipChange?() } }
    @Published var mouthOn: Bool { didSet { UserDefaults.standard.set(mouthOn, forKey: "mouthOn"); onBodyWhipChange?() } }
    var onBodyWhipChange: (() -> Void)?

    /// 일할 때(마우스 많이 움직이거나 타자) 돌아다니는 애들을 알아서 숨길지
    @Published var autoDodge: Bool {
        didSet { UserDefaults.standard.set(autoDodge, forKey: "autoDodge") }
    }

    /// 채찍질에 ⌥ 키가 꼭 필요한지 (의도치 않은 채찍 방지)
    @Published var whipNeedsOption: Bool {
        didSet { UserDefaults.standard.set(whipNeedsOption, forKey: "whipNeedsOption") }
    }

    static let ghostID = "ghost:claude"

    // 남은 쿼터 (당근은 그림일 뿐)
    @Published private(set) var quota: Quota? = nil
    @Published var quotaEnabled: Bool {
        didSet {
            UserDefaults.standard.set(quotaEnabled, forKey: "quotaEnabled")
            if quotaEnabled { explainKeychainOnce(); startQuota() } else { stopQuota() }
        }
    }
    /// 처음 켤 때: 곧 뜨는 건 Claude 로그인이 아니라 macOS 키체인 허용 창이라고 미리 알려 준다
    private func explainKeychainOnce() {
        guard !UserDefaults.standard.bool(forKey: "quotaExplained"), ProcessInfo.processInfo.environment["WHIPLASH_FAKE_QUOTA"] == nil else { return }
        UserDefaults.standard.set(true, forKey: "quotaExplained")
        let a = NSAlert()
        a.messageText = t("Heads up — a Keychain prompt is coming")
        a.informativeText = t("Remaining quota is read with the login token Claude Code keeps in your Keychain. macOS will now ask for your Mac login password because Whiplash wants to use that Keychain item (this is not a Claude login). Choose Always Allow and it won't ask again. The token is only used for the request and never stored.")
        a.addButton(withTitle: t("Got it"))
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
    private var quotaTimer: Timer?
    private func startQuota() {
        quotaTimer?.invalidate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refreshQuota() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        quotaTimer = timer
        refreshQuota()
    }
    private func stopQuota() { quotaTimer?.invalidate(); quotaTimer = nil; quota = nil }
    func refreshQuota() {
        guard quotaEnabled, !Paths.sandboxed else { return }
        QuotaReader.fetch { [weak self] r in
            guard let self = self else { return }
            switch r {
            case .success(let q):
                let wasExhausted = self.quota?.exhausted ?? false
                self.quota = q
                if q.exhausted && !wasExhausted { NSSound(named: "Sosumi")?.play() }     // 파업 시작
            case .failure(let e):
                self.quota = Quota(windows: self.quota?.windows ?? [],
                                   fetchedAt: self.quota?.fetchedAt ?? Date(), error: e.localizedDescription)
                // 키체인을 거부했거나 로그인이 없으면 다시 묻지 않는다 (5분마다 창이 뜨는 걸 막음). 「남은 쿼터 보기」를 껐다 켜면 다시 시도.
                if case .denied = e { self.quotaTimer?.invalidate(); self.quotaTimer = nil }
                if case .noToken = e { self.quotaTimer?.invalidate(); self.quotaTimer = nil }
            }
        }
    }

    /// 이 세션이 먹은 당근 (뽑힌 당근을 세션 먹이값 비율로 나눔). 쿼터 조회가 없거나 먹이값이 없으면 nil.
    /// 먹이값은 세션 시작부터 누적이라 5시간 창과 딱 맞진 않다 — 「누가 많이 먹었나」 비교용.
    func carrotsEaten(_ g: AgentGroup) -> Double? {
        guard quotaEnabled, let five = quota?.fiveHour, let s = g.session, s.costUSD > 0 else { return nil }
        let eaten = Double(CritterManager.carrotSlots) * five.utilization / 100
        let total = snapshot.groups.compactMap { $0.session?.costUSD }.reduce(0, +)
        guard total > 0 else { return nil }
        return eaten * s.costUSD / total
    }

    /// 파업 중: 쿼터가 바닥났거나(사용량 조회) 그 세션이 429 를 맞았다
    func onStrike(_ g: AgentGroup) -> Bool {
        if g.session?.onStrike == true { return true }
        return (quota?.exhausted ?? false) && (g.kind == .claudeCode || g.kind == .claudeApp) && g.id != Self.ghostID
    }

    /// 화남: 내 차례(답·질문·허락 기다림)인데 자꾸 때리면. id → (언제까지, 말풍선)
    @Published private(set) var angry: [String: (until: Date, line: String)] = [:]
    func isAngry(_ id: String) -> Bool { angry[id].map { $0.until > Date() } ?? false }

    static func playAngry() {
        if let url = Bundle.main.url(forResource: "angry", withExtension: "wav"), let s = NSSound(contentsOf: url, byReference: true) {
            s.volume = 0.9; s.play()
        } else { NSSound(named: "Basso")?.play() }
    }

    /// 채찍 면역 세션 (sessionId 기준, 재시작해도 유지)
    @Published private(set) var immune: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "immune") ?? [])
    func isImmune(_ g: AgentGroup) -> Bool { g.session.map { immune.contains($0.sessionId) } ?? false }
    func toggleImmune(_ g: AgentGroup) {
        guard let sid = g.session?.sessionId else { return }
        if immune.contains(sid) { immune.remove(sid) } else { immune.insert(sid) }
        UserDefaults.standard.set(Array(immune), forKey: "immune")
        NSSound(named: immune.contains(sid) ? "Blow" : "Pop")?.play()
    }

    // 채찍
    @Published private(set) var jobs: [pid_t: WhipJob] = [:]
    private var jobOwner: [pid_t: String] = [:]          // 보조 프로세스 pid → 채찍 맞은 칸 id
    @Published private(set) var results: [WhipResult] = []
    @Published private(set) var tasks: [WhipTask] = WhipRunner.loadTasks()
    @Published private(set) var lastStrike: [String: Date] = [:]
    @Published var hoverWhipID: String? = nil          // 커서가 올라간 채찍 맞을 칸
    @Published private(set) var lastSent: [String: Date] = [:]   // 지시를 보낸 칸 (반짝임)
    @Published private(set) var lastTreat: [String: Date] = [:]  // 간식 받은 칸 (냠!)
    @Published private(set) var treats: [String: Int] = [:]      // 세션별 간식 횟수

    // 오토 채찍질: 정한 시각까지 간격마다 쉬는 세션에 「계속해」
    @Published private(set) var autoWhipUntil: Date? {
        didSet { UserDefaults.standard.set(autoWhipUntil?.timeIntervalSince1970 ?? 0, forKey: "autoWhipUntil") }
    }
    @Published var autoWhipInterval: TimeInterval {
        didSet { UserDefaults.standard.set(autoWhipInterval, forKey: "autoWhipInterval") }
    }
    @Published private(set) var autoWhipCount = 0
    private var autoTimer: Timer?
    private var lastAutoWhip: [String: Date] = [:]
    private let whipRunner = WhipRunner()
    private var pendingWhips: Set<String> = []

    private let sampler = ProcessSampler()
    private let sessionReader = SessionReader()      // sampleQueue 에서만 쓴다
    private let sampleQueue = DispatchQueue(label: "com.kade.whiplash.sample", qos: .utility)
    private let storageQueue = DispatchQueue(label: "com.kade.whiplash.storage", qos: .background)
    private var sampleTimer: DispatchSourceTimer?
    private var storageTimer: DispatchSourceTimer?
    private var animTimer: Timer?
    private var awakeMemory: [String: Bool] = [:]
    private var visible = true

    init() {
        compact = UserDefaults.standard.object(forKey: "compact") == nil ? true : UserDefaults.standard.bool(forKey: "compact")   // 처음엔 작게 보기
        overloadMode = Self.overloadTest.map { OverloadMode(rawValue: $0) ?? .ask } ?? OverloadMode(rawValue: UserDefaults.standard.string(forKey: "overloadMode") ?? "") ?? .off
        overloadAfter = Self.overloadTest != nil ? 3 : (UserDefaults.standard.object(forKey: "overloadAfter") as? TimeInterval ?? 180)
        compactNames = UserDefaults.standard.object(forKey: "compactNames") as? Bool ?? true
        compactPerRow = UserDefaults.standard.object(forKey: "compactPerRow") == nil ? 10 : max(1, UserDefaults.standard.integer(forKey: "compactPerRow"))
        roaming = UserDefaults.standard.bool(forKey: "roaming")
        critterSmall = UserDefaults.standard.bool(forKey: "critterSmall")
        caged = UserDefaults.standard.bool(forKey: "caged")
        hidden = UserDefaults.standard.bool(forKey: "hidden")
        critterBox = UserDefaults.standard.bool(forKey: "critterBox")
        theme = UserDefaults.standard.string(forKey: "theme") ?? "glass"
        panelWithCritters = UserDefaults.standard.object(forKey: "panelWithCritters") as? Bool ?? false   // 기본: 둘 중 하나만
        dockIcon = UserDefaults.standard.object(forKey: "dockIcon") as? Bool ?? true
        whipNeedsOption = UserDefaults.standard.bool(forKey: "whipNeedsOption")
        autoDodge = UserDefaults.standard.object(forKey: "autoDodge") as? Bool ?? true
        demo = ProcessInfo.processInfo.environment["WHIPLASH_DEMO"] != nil || UserDefaults.standard.bool(forKey: "demo")
        headFlickOn = UserDefaults.standard.bool(forKey: "headFlickOn")
        handCamOn = UserDefaults.standard.bool(forKey: "handCamOn")
        remoteOn = UserDefaults.standard.bool(forKey: "remoteOn")
        mouthOn = UserDefaults.standard.bool(forKey: "mouthOn")
        quotaEnabled = UserDefaults.standard.bool(forKey: "quotaEnabled")
        autoWhipInterval = UserDefaults.standard.object(forKey: "autoWhipInterval") as? TimeInterval ?? 600
        let until = UserDefaults.standard.double(forKey: "autoWhipUntil")
        autoWhipUntil = until > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: until) : nil
        alwaysOnTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
    }

    /// 화면에 보이면 2초, 가려져 있으면 15초마다 잰다
    private var sampleInterval: DispatchTimeInterval { visible ? .seconds(2) : .seconds(15) }

    func start() {
        let sampler = self.sampler
        let reader = self.sessionReader
        let t = DispatchSource.makeTimerSource(queue: sampleQueue)
        t.schedule(deadline: .now(), repeating: sampleInterval, leeway: .milliseconds(400))
        t.setEventHandler { [weak self] in
            var snap = sampler.sample()
            let roots = snap.groups.filter { $0.kind == .claudeCode && !$0.id.hasPrefix("app:") }
            let sessions = reader.read(pids: roots.map { $0.rootPID },
                                       starts: Dictionary(uniqueKeysWithValues: roots.map { ($0.rootPID, $0.start) }))
            for i in snap.groups.indices { snap.groups[i].session = sessions[snap.groups[i].rootPID] }
            DispatchQueue.main.async { self?.apply(snap) }
        }
        t.resume()
        sampleTimer = t

        let s = DispatchSource.makeTimerSource(queue: storageQueue)
        s.schedule(deadline: .now() + 3, repeating: .seconds(1800), leeway: .seconds(30))
        s.setEventHandler { [weak self] in self?.scanStorageNow() }
        s.resume()
        storageTimer = s
        if autoWhipUntil != nil { startAutoTimer() }
        if quotaEnabled { startQuota() }
    }

    // MARK: - 오토 채찍질

    var autoWhipOn: Bool { autoWhipUntil.map { $0 > Date() } ?? false }

    func setAutoWhip(until: Date?) {
        autoWhipUntil = until
        autoWhipCount = 0
        lastAutoWhip = [:]
        if until != nil { startAutoTimer(); Self.playWhip() } else { autoTimer?.invalidate(); autoTimer = nil }
    }

    private func startAutoTimer() {
        autoTimer?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.autoTick() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        autoTimer = t
        autoTick()
    }

    /// 20초마다: 시각이 지났으면 끝. 아니면 간격이 지난 쉬는 세션에 채찍 (허락 기다리는 건 건너뜀)
    private func autoTick() {
        guard let until = autoWhipUntil else { return }
        if Date() >= until {
            setAutoWhip(until: nil)
            NSSound(named: "Glass")?.play()
            return
        }
        let now = Date()
        var struck = false
        for g in snapshot.groups {
            guard let s = g.session, s.status == .idle, s.waiting != .permission, s.socketPath != nil,
                  g.whipJob == nil, !Paths.sandboxed, !immune.contains(s.sessionId), !onStrike(g) else { continue }
            if let last = lastAutoWhip[g.id], now.timeIntervalSince(last) < autoWhipInterval { continue }
            if let since = s.statusSince, now.timeIntervalSince(since) < 60 { continue }   // 방금 멈춘 애는 숨 돌리게
            lastAutoWhip[g.id] = now
            lastStrike[g.id] = now
            onStrike?(g.id)
            struck = true
            SessionMessenger.send(WhipWords.load(), to: s) { [weak self] r in
                guard let self = self else { return }
                if case .success = r { self.autoWhipCount += 1; self.lastSent[g.id] = Date() }
            }
        }
        if struck { Self.playWhip() }
    }

    func rescanStorage() {
        storageQueue.async { [weak self] in self?.scanStorageNow() }
    }

    func setVisible(_ v: Bool) {
        guard v != visible else { return }
        visible = v
        sampleTimer?.schedule(deadline: .now() + (v ? .milliseconds(100) : sampleInterval),
                              repeating: sampleInterval, leeway: .milliseconds(400))
        updateAnimation()
    }

    var loginItemEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Whiplash login item: \(error)")
            }
            objectWillChange.send()
        }
    }

    // MARK: - 채찍

    /// 이 칸에 채찍을 쓸 수 있나. 일하는 애도 맞는다 (더 빨리!). 이미 채찍 맞고 일하는 중이면 리액션만.
    func canWhip(_ g: AgentGroup) -> Bool {
        if isImmune(g) { return false }
        if g.id.hasPrefix("app:") || g.id == Self.ghostID { return true }
        return WhipRunner.canRun(g.kind) && g.dir != nil && g.dir != "/"
    }

    private func isBusy(kind: AgentKind, dir: String) -> Bool {
        pendingWhips.contains(kind.rawValue + dir) || jobs.values.contains { $0.kind == kind && $0.dir == dir }
    }

    /// task 가 nil 이면 아무 일이나 골라서 시킨다
    /// staggered: 여러 마리를 한 번에 칠 때 — 반응(소리·펄쩍)은 바로, 메시지 전달은 줄 세워 하나씩 (deliveryGap 간격)
    /// allowHelper: 세션에 못 보냈을 때 보조 에이전트를 띄워도 되나 (여러 마리일 땐 한꺼번에 뜨지 않게 막는다)
    func whip(_ g: AgentGroup, task: WhipTask? = nil, silent: Bool = false, staggered: Bool = false, allowHelper: Bool = true) {
        if isImmune(g) { if !silent { NSSound(named: "Tink")?.play() }; return }      // 면역: 맞지 않는다
        let streak = hit(g.id)
        if onStrike(g) {                                                // 파업: 쿼터가 없는데 때리면 화만 낸다
            angry[g.id] = (Date().addingTimeInterval(8), (streak >= 2 ? t("No quota, I said!!") : t("I'm out of quota!!")))
            lastStrike[g.id] = Date()
            Self.playAngry()
            onStrike?(g.id)
            return
        }
        // 내 차례인데 (할 일이 없거나 결정을 기다리는데) 자꾸 때리면 화낸다. 메시지도 안 보낸다.
        if let s = g.session, s.needsYou, streak >= 2 {
            let rude = streak >= 3                        // 두 번째는 존댓말, 세 번째부터 반말
            let line: String
            switch s.waiting {
            case .question, .permission: line = t(rude ? t("Just say something already!!") : t("You need to tell me what to do!!"))
            case .reply:                 line = t(rude ? t("Give me work then!!") : t("I need something to do!!"))
            case .none:                  line = t(rude ? t("Stop hitting me!!") : t("Why are you hitting me?!"))
            }
            angry[g.id] = (Date().addingTimeInterval(8), line)
            lastStrike[g.id] = Date()
            Self.playAngry()
            onStrike?(g.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.2) { [weak self] in
                guard let self = self, let a = self.angry[g.id], a.until <= Date() else { return }
                self.angry[g.id] = nil
            }
            return
        }
        lastStrike[g.id] = Date()
        if !silent { Self.playWhip(streak); Self.haptic(1) }
        onStrike?(g.id)
        // 여기까지가 반응. 아래는 전달: 여러 마리면 줄 세워 하나씩 (세션 아홉이 한순간에 턴을 시작하면 맥 전체가 버벅인다)
        let id = g.id
        let work = { [weak self] in
            guard let self = self else { return }
            self.deliver(self.snapshot.groups.first(where: { $0.id == id }) ?? g, task: task, allowHelper: allowHelper)
        }
        if staggered && !Paths.sandboxed { enqueueDelivery(work) } else { work() }
    }

    /// 채찍의 실제 전달 (세션에 프롬프트 넣기·앱 앞으로·보조 에이전트)
    private func deliver(_ g: AgentGroup, task: WhipTask?, allowHelper: Bool) {
        if demo || ProcessInfo.processInfo.environment["WHIPLASH_DRY_WHIP"] != nil {   // 데모·개발용: 소리만
            NSLog("EOHANG whip %@", g.id)
            return
        }
        if isImmune(g) { return }                 // 줄 서 있는 사이 면역이 됐으면 건너뛴다
        if g.id == Self.ghostID {                 // 꺼진 클로드: 채찍으로 깨운다
            wakeClaude(dir: nil)
            return
        }

        if g.id.hasPrefix("app:") {
            // 데스크톱 앱은 앞으로 불러내기만
            NSRunningApplication(processIdentifier: g.rootPID)?.activate(options: [.activateAllWindows])
            return
        }
        if Paths.sandboxed {
            // 앱스토어판: 샌드박스 안에서는 새 에이전트를 못 띄우니 창만 앞으로
            bringToFront(g)
            return
        }
        if g.rootPID == 0 { return }
        // Claude Code 세션이면 본인에게 「계속해」를 넣는다 (일감을 고른 게 아닐 때). 못 보내면 보조 일감으로.
        if task == nil, let s = g.session, s.socketPath != nil, !Paths.sandboxed {
            SessionMessenger.send(WhipWords.load(), to: s) { [weak self] r in
                guard let self = self else { return }
                switch r {
                case .success: self.lastSent[g.id] = Date()
                case .failure: if allowHelper { self.whipHelper(g, task: nil) }
                }
            }
            return
        }
        if allowHelper { whipHelper(g, task: task) }
    }

    // MARK: 전달 줄 — 여러 마리를 한 번에 쳤을 때 메시지를 deliveryGap 간격으로 하나씩
    static let deliveryGap: TimeInterval = 3
    private var deliveryQueue: [() -> Void] = []
    private var deliveryTimer: Timer?
    var pendingDeliveries: Int { deliveryQueue.count }
    private func enqueueDelivery(_ work: @escaping () -> Void) {
        deliveryQueue.append(work)
        if deliveryTimer == nil { pumpDelivery() }      // 첫 번째는 바로, 다음부터 간격을 둔다
    }
    private func pumpDelivery() {
        guard !deliveryQueue.isEmpty else { return }
        deliveryQueue.removeFirst()()
        let t = Timer(timeInterval: Self.deliveryGap, repeats: false) { [weak self] _ in
            self?.deliveryTimer = nil
            self?.pumpDelivery()
        }
        RunLoop.main.add(t, forMode: .common)
        deliveryTimer = t
    }

    /// 보조 에이전트를 하나 띄워 읽기 전용 일감을 시킨다. 이미 채찍 일이 돌고 있으면 「짝!」만.
    private func whipHelper(_ g: AgentGroup, task: WhipTask?) {
        // 홈 폴더나 / 에서는 보조 에이전트를 안 띄운다 (ChatGPT 앱 속 codex 처럼 작업 폴더가 ~ 인 프로세스가 맞았을 때 홈 전체를 읽히지 않게)
        guard let dir = g.dir, dir != "/", dir != Paths.home, dir != NSHomeDirectory(),
              WhipRunner.canRun(g.kind), g.whipJob == nil, !isBusy(kind: g.kind, dir: dir),
              let t = task ?? tasks.randomElement() else { return }

        let key = g.kind.rawValue + dir
        let ownerID = g.id
        pendingWhips.insert(key)
        whipRunner.launch(kind: g.kind, dir: dir, task: t, started: { [weak self] job in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingWhips.remove(key)
                self.jobs[job.pid] = job
                self.jobOwner[job.pid] = ownerID
                self.snapshot = self.merged(self.snapshot)
            }
        }, finished: { [weak self] job, result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingWhips.remove(key)
                if let job = job { self.jobs[job.pid] = nil; self.jobOwner[job.pid] = nil }
                self.results.insert(result, at: 0)
                if self.results.count > 3 { self.results.removeLast(self.results.count - 3) }
                NSSound(named: result.ok ? "Glass" : "Basso")?.play()
            }
        })
    }

    /// 단축키: 쉬는 애 중 아무나 채찍
    func whipRandom() {
        let targets = snapshot.groups.filter { canWhip($0) && !$0.id.hasPrefix("app:") }
        if let g = targets.randomElement() { whip(g) } else { NSSound(named: "Basso")?.play() }
    }

    /// 간식(칭찬): 채찍의 반대. 세션에 칭찬 프롬프트를 보내고 「냠!」 반응. 메시지를 못 받는 애도 반응은 한다.
    static let broadcastID = "broadcast:all"
    static func playYum() { NSSound(named: "Purr")?.play() }
    func treat(_ g: AgentGroup, silent: Bool = false) {
        lastTreat[g.id] = Date()
        treats[g.id, default: 0] += 1
        if !silent { Self.playYum(); Self.haptic(1) }
        onStrike?(g.id)                                             // 폴짝
        if demo || ProcessInfo.processInfo.environment["WHIPLASH_DRY_WHIP"] != nil { NSLog("EOHANG treat %@", g.id); return }
        guard let s = g.session, !Paths.sandboxed else { return }
        SessionMessenger.send(TreatWords.load(), to: s) { _ in }
    }
    func treat(id: String) {
        guard let g = snapshot.groups.first(where: { $0.id == id }) else { return }
        treat(g)
    }
    /// 일하는 애 전부 간식
    func treatAll() {
        let targets = snapshot.groups.filter { $0.awake && !$0.id.hasPrefix("app:") && $0.id != Self.ghostID }
        guard !targets.isEmpty else { NSSound(named: "Basso")?.play(); return }
        for g in targets { treat(g, silent: true) }
        Self.playYum(); Self.haptic(min(targets.count, 3))
    }
    func editTreatWords() {
        _ = TreatWords.load()
        NSWorkspace.shared.open(TreatWords.file)
    }

    /// 확성기: 같은 말을 Claude 세션 전부에게
    func broadcast(_ text: String, completion: @escaping (Int, Int) -> Void) {
        let targets = snapshot.groups.filter { $0.session != nil && $0.id != Self.ghostID }
        guard !targets.isEmpty else { completion(0, 0); return }
        var ok = 0, done = 0
        for g in targets {
            send(text, to: g) { r in
                if case .success = r { ok += 1 }
                done += 1
                if done == targets.count { completion(ok, targets.count) }
            }
        }
    }

    /// 「전부 채찍」이 치는 애들: 쉬는 애만. 일하는 중이거나 허락을 기다리는 세션은 뺀다
    /// (일하는 세션에 「계속해」가 쌓이면 턴이 끝날 때마다 덤으로 또 돈다 — 자동 채찍과 같은 기준).
    /// 한 마리를 골라 치는 건 여전히 일하는 애도 맞는다.
    func whipAllTargets() -> [AgentGroup] {
        snapshot.groups.filter { g in
            guard canWhip(g), !g.id.hasPrefix("app:"), !isImmune(g) else { return false }
            if g.id == Self.ghostID { return true }
            if let s = g.session {
                guard s.waiting != .permission else { return false }
                return s.status == .idle || (s.status == .unknown && !g.awake)
            }
            return !g.awake
        }
    }

    /// 줄 세워 놓고 한 번에: 쉬는 애 전부 (소리는 겹쳐서 한 번)
    func whipAll() {
        let targets = whipAllTargets()
        guard !targets.isEmpty else { NSSound(named: "Basso")?.play(); return }
        whipMany(targets.map { $0.id })
    }

    /// 여러 마리를 한 번에 (전부 채찍·마우스로 휘둘러 지나간 애들). 반응은 다 같이 바로, 메시지는 한 세션씩 간격을 두고.
    /// 보조 에이전트는 통틀어 하나까지만: 소켓이 있는 세션은 전송이 실패해도 안 띄우고, 소켓 없는 애는 첫 번째만.
    func whipMany(_ ids: [String]) {
        var n = 0
        var helperLeft = 1
        for id in ids {
            guard let g = snapshot.groups.first(where: { $0.id == id }), canWhip(g), !isImmune(g) else { continue }
            let direct = g.session?.socketPath != nil
            let helper = !direct && helperLeft > 0
            if helper { helperLeft -= 1 }
            whip(g, silent: true, staggered: ids.count > 1, allowHelper: helper)
            n += 1
        }
        if n > 0 { Self.playWhipChorus(n) }
    }

    /// 마우스로 후려친 칸
    func whip(id: String) {
        guard let g = snapshot.groups.first(where: { $0.id == id }), canWhip(g) else { return }
        whip(g)
    }

    func reloadTasks() { tasks = WhipRunner.loadTasks() }

    func editWhipWords() {
        _ = WhipWords.load()
        NSWorkspace.shared.open(WhipWords.file)
    }

    func editTasks() {
        _ = WhipRunner.loadTasks()
        NSWorkspace.shared.open(WhipRunner.tasksFile)
    }

    func openResults() {
        try? FileManager.default.createDirectory(at: WhipRunner.resultsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(WhipRunner.resultsFolder)
    }

    func open(_ r: WhipResult) {
        if let f = r.file { NSWorkspace.shared.open(f) } else { openResults() }
    }

    // MARK: - 세션에 지시 보내기

    /// 떠 있는 세션에 사용자 메시지로 넣는다 (Claude 창에서 → 누르는 것과 같음)
    func send(_ text: String, to g: AgentGroup, completion: @escaping (Result<String, SessionMessenger.Failure>) -> Void) {
        guard let s = g.session else { completion(.failure(.noSocket)); return }
        if demo { lastSent[g.id] = Date(); NSSound(named: "Tink")?.play(); completion(.success("demo")); return }
        SessionMessenger.send(text, to: s) { [weak self] r in
            if case .success = r {
                self?.lastSent[g.id] = Date()
                NSSound(named: "Tink")?.play()
            } else {
                NSSound(named: "Basso")?.play()
            }
            completion(r)
        }
    }

    // MARK: - 세션 관리

    func openFolder(_ g: AgentGroup) {
        guard let d = g.dir else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: d, isDirectory: true))
    }

    func openTranscript(_ g: AgentGroup) {
        guard let t = g.session?.transcript else { return }
        NSWorkspace.shared.open(t)
    }

    func copyPrompt(_ g: AgentGroup) {
        guard let p = g.session?.lastPrompt, !p.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(p, forType: .string)
    }

    /// 세션을 띄운 앱(Claude 앱, 터미널, IDE)을 앞으로 불러온다: 부모를 거슬러 올라가 독에 뜨는 앱을 찾는다
    /// 「에이전트에게 가기」: 그 세션이 보이는 바로 그 자리로.
    ///  1) Claude 데스크톱 앱 안의 세션 → 앱의 딥링크 claude://code/continue?session=local_… (앱이 그 세션 화면으로 넘어간다)
    ///  2) 터미널(Terminal·iTerm) 탭에서 도는 세션 → tty 가 같은 탭을 고르고 그 창을 앞으로 (직접 배포판만, 처음에 「제어 허용」을 묻는다)
    ///  3) 그 밖 → 그 세션을 돌리는 앱을 앞으로
    func bringToFront(_ g: AgentGroup) {
        if let s = g.session, s.isDesktop, let id = s.hostSessionId,
           id.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
           let url = URL(string: "claude://code/continue?session=" + id) {
            NSWorkspace.shared.open(url)
            return
        }
        guard let host = hostApp(of: g.rootPID) else { return }
        if !Paths.sandboxed, let tty = Self.tty(of: g.rootPID), Self.selectTerminalTab(tty: tty, bundleID: host.bundleIdentifier ?? "") {
            host.activate(options: [])           // 고른 탭의 창만 앞으로
            return
        }
        host.activate(options: [.activateAllWindows])
    }

    /// 프로세스 줄기를 거슬러 올라가 처음 만나는 보통 앱 (터미널·에디터·Claude 앱)
    private func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var cur = pid
        var hops = 0
        while hops < 16, cur > 1 {
            if let app = NSRunningApplication(processIdentifier: cur), app.activationPolicy == .regular { return app }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(cur, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            cur = pid_t(bitPattern: info.pbi_ppid)
            hops += 1
        }
        return nil
    }

    /// 그 프로세스의 제어 터미널 ("/dev/ttys012"). 터미널 없이 도는 것이면 nil.
    private static func tty(of pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.e_tdev != 0, info.e_tdev != UInt32.max,
              let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR) else { return nil }
        let s = String(cString: name)
        return s.hasPrefix("tty") ? "/dev/" + s : nil
    }

    /// Terminal·iTerm 에서 tty 가 같은 탭을 골라 그 창을 맨 앞으로. 골랐으면 true.
    private static func selectTerminalTab(tty: String, bundleID: String) -> Bool {
        guard tty.range(of: "^/dev/ttys?[0-9a-z]+$", options: .regularExpression) != nil else { return false }
        let source: String
        switch bundleID {
        case "com.apple.Terminal":
            source = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            source = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      select t
                      select s
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default:
            return false
        }
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return r?.booleanValue ?? false
    }

    /// 터미널에서 Ctrl-C 를 누른 것과 같다. 지금 하던 일만 멈추고 세션은 남는다.
    func interrupt(_ g: AgentGroup) {
        guard g.session?.status == .busy else { return }
        kill(g.rootPID, SIGINT)
        NSSound(named: "Pop")?.play()
    }

    func dismiss(_ r: WhipResult) { results.removeAll { $0.id == r.id } }

    /// Whiplash 를 닫을 때 채찍 맞고 일하던 녀석들도 같이 멈춘다
    func stopJobs() {
        for pid in jobs.keys { kill(pid, SIGTERM) }
    }

    // MARK: -

    private func scanStorageNow() {
        let items = StorageScanner.scan()
        let d = StorageScanner.disk()
        DispatchQueue.main.async { [weak self] in
            self?.storage = items
            self?.disk = d
        }
    }

    private func apply(_ incoming: Snapshot) {
        var s = incoming
        var next: [String: Bool] = [:]
        for i in s.groups.indices {
            let was = awakeMemory[s.groups[i].id] ?? false
            let c = s.groups[i].cpu
            let on: Bool
            if let st = s.groups[i].session?.status, st != .unknown {
                // Claude Code 는 자기가 일하는 중인지 직접 알려 준다
                on = st == .busy
            } else {
                // 코어 4% 넘게 쓰면 일하는 중. 깜빡거리지 않게 내려갈 때는 1.5%까지 봐준다.
                on = c > 0.04 || (was && c > 0.015)
            }
            s.groups[i].awake = on
            next[s.groups[i].id] = on
        }
        awakeMemory = next
        snapshot = merged(s)
        updateAnimation()
        checkAlerts()
    }

    // MARK: 알림 판정 (새 표본이 올 때마다)

    private func alertable(_ g: AgentGroup) -> Bool { !g.id.hasPrefix("app:") && g.id != Self.ghostID }
    func alertName(_ g: AgentGroup) -> String { (g.session?.name).flatMap { $0.isEmpty ? nil : $0 } ?? g.label }
    /// 여기서 멈출 수 있나 (Ctrl-C = SIGINT). Claude Code 세션은 일하는 중일 때만, 데스크톱 앱 속 세션과 앱스토어판은 안 됨.
    func canStop(_ g: AgentGroup) -> Bool {
        guard !Paths.sandboxed, alertable(g), g.rootPID > 0 else { return false }
        if let s = g.session { return s.status == .busy && !s.isDesktop }
        return true
    }

    private func checkAlerts() {
        let now = Date()
        let groups = snapshot.groups.filter(alertable)
        let live = Set(groups.map { $0.id })
        var next = alerts.filter { live.contains($0.groupID) }                       // 사라진 애의 알림은 지운다
        next.removeAll { if case .risk = $0.kind { return now.timeIntervalSince($0.raisedAt) > 600 } else { return false } }   // 유출 알림은 10분 뒤 접는다

        // 과부하: overloadAfter 동안 이어지면 한 번 묻는다. 20초 넘게 식어 있으면 처음부터 다시 센다.
        let watchOverload = overloadMode != .off && (!demo || Self.overloadTest != nil)
        for g in groups {
            let hot = watchOverload && g.overloaded(memTotal: snapshot.memTotal)
            if hot {
                overloadSince[g.id] = overloadSince[g.id] ?? now
                overloadLastHot[g.id] = now
            } else if let last = overloadLastHot[g.id], now.timeIntervalSince(last) > 20 || !watchOverload {
                overloadSince[g.id] = nil; overloadLastHot[g.id] = nil; overloadSettled.remove(g.id)
                next.removeAll { $0.id == "overload:" + g.id }
            }
            if hot, let since = overloadSince[g.id], now.timeIntervalSince(since) >= overloadAfter,
               !overloadSettled.contains(g.id), !next.contains(where: { $0.id == "overload:" + g.id }) {
                next.append(AgentAlert(id: "overload:" + g.id, groupID: g.id, kind: .overload, raisedAt: now, since: since))
                NSSound(named: "Funk")?.play()
            }
        }
        for id in Array(overloadSince.keys) where !live.contains(id) { overloadSince[id] = nil; overloadLastHot[id] = nil; overloadSettled.remove(id) }

        // 유출 감시: 세션 기록에서 잡힌 새 위험 한 건마다 알리고(+설정에 따라 경고 프롬프트)
        if leakGuard != "off" {
            for g in groups {
                for r in g.session?.risks ?? [] where !risksSeen.contains(r.id) {
                    risksSeen.insert(r.id)
                    next.append(AgentAlert(id: "risk:" + r.id, groupID: g.id, kind: .risk(title: r.title, detail: r.detail), raisedAt: now, since: r.at))
                    Self.playAngry()
                    if leakGuard == "whip" { warn(g, title: r.title, detail: r.detail) }
                }
            }
            if risksSeen.count > 400 { risksSeen = Set(groups.flatMap { $0.session?.risks.map { $0.id } ?? [] }) }
        }
        setAlerts(Array(next.suffix(6)))
    }

    private func setAlerts(_ next: [AgentAlert]) {
        guard next != alerts else { return }
        alerts = next
        if alerts.isEmpty { alertTimer?.invalidate(); alertTimer = nil }
        else if alertTimer == nil {                          // 자동 멈춤 카운트다운은 표본 주기(2~15초)보다 촘촘히 본다
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.alertTick() }
            RunLoop.main.add(t, forMode: .common)
            alertTimer = t
        }
        onAlertsChanged?()
    }
    private func dropAlerts(_ match: (AgentAlert) -> Bool) { setAlerts(alerts.filter { !match($0) }) }

    private func alertTick() {
        guard overloadMode == .auto else { return }
        let now = Date()
        for a in alerts where a.kind == .overload && now.timeIntervalSince(a.raisedAt) >= Self.overloadCountdown {
            answer(a, stop: true)                            // 답이 없었다 → 멈춘다 (멈출 수 없는 애면 그냥 접는다)
        }
    }

    /// 알림 한 줄에 대한 답: stop = 멈추기(Ctrl-C), 아니면 그냥 두기
    func answer(_ a: AgentAlert, stop: Bool) {
        if stop, let g = snapshot.groups.first(where: { $0.id == a.groupID }), canStop(g) {
            if demo || ProcessInfo.processInfo.environment["WHIPLASH_DRY_WHIP"] != nil { NSLog("EOHANG stop %@", g.id) }
            else { kill(g.rootPID, SIGINT) }
            NSSound(named: "Pop")?.play()
        }
        if a.kind == .overload { overloadSettled.insert(a.groupID) }
        dropAlerts { $0.id == a.id }
    }

    /// 유출 경고: 채찍 반응 + 「멈추고 되돌려」 프롬프트 (세션에 보낼 수 있을 때만)
    func warn(_ g: AgentGroup, title: String, detail: String) {
        lastStrike[g.id] = Date()
        onStrike?(g.id)
        if demo || ProcessInfo.processInfo.environment["WHIPLASH_DRY_WHIP"] != nil { NSLog("EOHANG guard-warn %@ %@", g.id, title); return }
        guard let s = g.session, s.socketPath != nil, !Paths.sandboxed else { return }
        SessionMessenger.send(LeakGuard.warning(title: title, detail: detail), to: s) { [weak self] r in
            if case .success = r { self?.lastSent[g.id] = Date() }
        }
    }

    /// 개발용: 가짜 유출 한 건을 첫 세션에 붙인다 (WHIPLASH_GUARD_TEST)
    func injectTestRisk() {
        guard let i = snapshot.groups.firstIndex(where: { $0.session != nil && alertable($0) }) else { return }
        var s = snapshot
        s.groups[i].session?.risks.append(SessionRisk(id: "test-\(Int(Date().timeIntervalSince1970))", title: "Staging a secrets file for git",
                                                      detail: "git add .env && git commit -m \"config\"", at: Date()))
        snapshot = s
        checkAlerts()
    }

    /// Claude 가 하나도 안 떠 있으면 「자는 클로드」 유령 칸을 하나 보여 준다 (휘두르면 깨움)
    private func withGhost(_ incoming: Snapshot) -> Snapshot {
        let claudeUp = incoming.groups.contains { ($0.kind == .claudeCode || $0.kind == .claudeApp) && $0.id != Self.ghostID }
        let force = ProcessInfo.processInfo.environment["WHIPLASH_GHOST"] != nil
        guard !claudeUp || force else { return incoming }
        var s = incoming
        s.groups.append(AgentGroup(id: Self.ghostID, kind: .claudeCode, label: t("off"), rootPID: 0, start: 0))
        return s
    }

    private func merged(_ incoming: Snapshot) -> Snapshot {
        var s = mergedReal(incoming)
        if demo { s.groups = Self.demoGroups() }
        return s
    }

    /// 데모용 가짜 에이전트 7마리: 종류·상태·활동을 골고루
    static func demoGroups() -> [AgentGroup] {
        func session(_ pid: pid_t, _ name: String, _ cwd: String, busy: Bool, activity: String, chore: Chore, waiting: AgentSession.Waiting, cost: Double, reply: String = "") -> AgentSession {
            var s = AgentSession(pid: pid, sessionId: "demo-\(pid)", cwd: cwd, name: name, status: busy ? .busy : .idle,
                                 startedAt: Date().addingTimeInterval(-3600 * Double(pid % 5 + 1)), statusSince: Date().addingTimeInterval(-60 * Double(pid % 9 + 1)),
                                 entrypoint: "cli")
            s.activity = activity; s.chore = chore; s.waiting = waiting; s.costUSD = cost; s.tokens = Int(cost * 180_000); s.lastReply = reply
            s.linesAdded = Int(cost * 40); s.linesRemoved = Int(cost * 9)
            return s
        }
        func group(_ id: String, _ kind: AgentKind, _ label: String, _ pid: pid_t, cpu: Double, mem: UInt64, awake: Bool, session: AgentSession? = nil) -> AgentGroup {
            var g = AgentGroup(id: id, kind: kind, label: label, rootPID: pid, start: 0)
            g.dir = "/Users/demo/" + label; g.cpu = cpu; g.memory = mem; g.processCount = 1 + Int(cpu * 3); g.awake = awake; g.session = session
            return g
        }
        let mb: UInt64 = 1_048_576
        return [
            group("cli:9001", .claudeCode, "shop-api", 9001, cpu: 0.9, mem: 420 * mb, awake: true,
                  session: session(9001, "Refactor the checkout flow", "/Users/demo/shop-api", busy: true, activity: t("Editing · CartService.swift"), chore: .write, waiting: .none, cost: 12.4)),
            group("cli:9002", .claudeCode, "docs-site", 9002, cpu: 0.0, mem: 310 * mb, awake: false,
                  session: session(9002, "Write the onboarding guide", "/Users/demo/docs-site", busy: false, activity: t("Answering"), chore: .answer, waiting: .reply, cost: 4.1, reply: "Draft is ready. Want me to add screenshots?")),
            group("cli:9003", .claudeCode, "mobile", 9003, cpu: 0.0, mem: 365 * mb, awake: false,
                  session: session(9003, "Fix login crash on iOS 17", "/Users/demo/mobile", busy: false, activity: t("Asking you"), chore: .answer, waiting: .question, cost: 7.8)),
            group("cli:9004", .claudeCode, "data-pipeline", 9004, cpu: 1.7, mem: 2_300 * mb, awake: true,
                  session: session(9004, "Backfill 2025 events", "/Users/demo/data-pipeline", busy: true, activity: t("Running · pytest -x"), chore: .run, waiting: .none, cost: 31.2)),
            group("cli:9005", .codex, "landing", 9005, cpu: 0.4, mem: 210 * mb, awake: true),
            group("cli:9006", .cursor, "design-system", 9006, cpu: 0.1, mem: 540 * mb, awake: false),
            group("app:antigravity", .antigravity, t("app"), 9007, cpu: 0.2, mem: 890 * mb, awake: true),
        ]
    }

    /// 채찍 맞고 뛰는 보조 프로세스를 채찍 맞은 칸에 합친다: 그 칸이 일하는 것처럼 보이고, 보조 줄은 숨긴다
    private func mergedReal(_ incoming: Snapshot) -> Snapshot {
        guard !jobs.isEmpty else { return withGhost(incoming) }
        var s = incoming
        var helpers: [String: AgentGroup] = [:]        // owner id → 보조
        s.groups.removeAll { g in
            if let job = jobs[g.rootPID], let owner = jobOwner[g.rootPID] {
                var h = g; h.whipJob = job
                helpers[owner] = h
                return true
            }
            return false
        }
        for i in s.groups.indices {
            if let h = helpers[s.groups[i].id] {
                s.groups[i].whipJob = h.whipJob
                s.groups[i].cpu += h.cpu
                s.groups[i].memory += h.memory
                s.groups[i].processCount += h.processCount
                s.groups[i].awake = true
            }
        }
        // 채찍 맞은 칸이 사라졌으면 (세션 종료) 보조를 그대로 보여 준다
        for (owner, h) in helpers where !s.groups.contains(where: { $0.id == owner }) {
            s.groups.append(h)
        }
        return withGhost(s)
    }

    // MARK: - 꺼진 클로드 깨우기

    /// dir 이 있으면 터미널에서 그 폴더로 claude 를, 없으면 Claude 앱을 연다
    func wakeClaude(dir: String?) {
        if let dir = dir {
            // .command 파일을 열면 터미널이 실행한다 (Apple 이벤트 권한 없이)
            let safe = (dir as NSString).lastPathComponent.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
            let url = WhipRunner.folder.appendingPathComponent("wake-\(safe).command")
            let quoted = dir.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "#!/bin/zsh -l\ncd \"\(quoted)\" && exec claude\n"
            try? FileManager.default.createDirectory(at: WhipRunner.folder, withIntermediateDirectories: true)
            try? script.write(to: url, atomically: true, encoding: .utf8)
            chmod(url.path, 0o755)
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            wakeClaude(dir: Paths.home)
        }
    }

    /// 최근에 Claude Code 를 쓴 프로젝트 폴더들 (~/.claude/projects 기록 기준)
    func recentProjects() -> [String] { sessionReader.recentProjects() }

    /// 일하는 캐릭터가 있고 화면에 보일 때만 0.6초 박자로 통통. 아니면 타이머 자체를 끈다.
    private func updateAnimation() {
        let need = visible && snapshot.groups.contains { $0.awake }
        if need, animTimer == nil {
            let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
                self?.tick &+= 1
            }
            t.tolerance = 0.15
            RunLoop.main.add(t, forMode: .common)
            animTimer = t
        } else if !need, let t = animTimer {
            t.invalidate()
            animTimer = nil
        }
    }
}
