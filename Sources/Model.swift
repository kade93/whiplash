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

    /// 8초 안에 연타하면 횟수가 올라간다 (소리·리액션이 달라짐)
    private var hitStreak: [String: (count: Int, at: Date)] = [:]
    func hit(_ id: String) -> Int {
        let now = Date()
        let n = (hitStreak[id].map { now.timeIntervalSince($0.at) < 8 ? $0.count + 1 : 1 }) ?? 1
        hitStreak[id] = (n, now)
        return n
    }

    /// 채찍질에 ⌥ 키가 꼭 필요한지 (의도치 않은 채찍 방지)
    @Published var whipNeedsOption: Bool {
        didSet { UserDefaults.standard.set(whipNeedsOption, forKey: "whipNeedsOption") }
    }

    static let ghostID = "ghost:claude"

    // 당근밭 (쿼터)
    @Published private(set) var quota: Quota? = nil
    @Published var quotaEnabled: Bool {
        didSet { UserDefaults.standard.set(quotaEnabled, forKey: "quotaEnabled"); quotaEnabled ? startQuota() : stopQuota() }
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
                self.quota = Quota(fiveHour: self.quota?.fiveHour, sevenDay: self.quota?.sevenDay,
                                   fetchedAt: self.quota?.fetchedAt ?? Date(), error: e.localizedDescription)
            }
        }
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
    private let sampleQueue = DispatchQueue(label: "kr.urbanism.whiplash.sample", qos: .utility)
    private let storageQueue = DispatchQueue(label: "kr.urbanism.whiplash.storage", qos: .background)
    private var sampleTimer: DispatchSourceTimer?
    private var storageTimer: DispatchSourceTimer?
    private var animTimer: Timer?
    private var awakeMemory: [String: Bool] = [:]
    private var visible = true

    init() {
        compact = UserDefaults.standard.bool(forKey: "compact")
        roaming = UserDefaults.standard.bool(forKey: "roaming")
        critterSmall = UserDefaults.standard.bool(forKey: "critterSmall")
        caged = UserDefaults.standard.bool(forKey: "caged")
        hidden = UserDefaults.standard.bool(forKey: "hidden")
        critterBox = UserDefaults.standard.bool(forKey: "critterBox")
        panelWithCritters = UserDefaults.standard.object(forKey: "panelWithCritters") as? Bool ?? false   // 기본: 둘 중 하나만
        dockIcon = UserDefaults.standard.object(forKey: "dockIcon") as? Bool ?? true
        whipNeedsOption = UserDefaults.standard.bool(forKey: "whipNeedsOption")
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
    func whip(_ g: AgentGroup, task: WhipTask? = nil) {
        if isImmune(g) { NSSound(named: "Tink")?.play(); return }      // 면역: 맞지 않는다
        let streak = hit(g.id)
        if onStrike(g) {                                                // 파업: 쿼터가 없는데 때리면 화만 낸다
            angry[g.id] = (Date().addingTimeInterval(8), t(streak >= 2 ? "쿼터 없다고!!" : "쿼터가 없어요!!"))
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
            case .question, .permission: line = t(rude ? t("말을 해야 할 거 아냐!!") : t("말을 해야 하죠!!!"))
            case .reply:                 line = t(rude ? t("할 일을 줘야지!!") : t("할 일을 주셔야죠!!"))
            case .none:                  line = t(rude ? t("왜 때려!!") : t("왜 때리세요!!"))
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
        Self.playWhip(streak)
        onStrike?(g.id)
        if ProcessInfo.processInfo.environment["WHIPLASH_DRY_WHIP"] != nil {   // 개발용: 소리만
            NSLog("EOHANG whip %@", g.id)
            return
        }
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
                case .failure: self.whipHelper(g, task: nil)
                }
            }
            return
        }
        whipHelper(g, task: task)
    }

    /// 보조 에이전트를 하나 띄워 읽기 전용 일감을 시킨다. 이미 채찍 일이 돌고 있으면 「짝!」만.
    private func whipHelper(_ g: AgentGroup, task: WhipTask?) {
        guard let dir = g.dir, WhipRunner.canRun(g.kind), g.whipJob == nil, !isBusy(kind: g.kind, dir: dir),
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
    func bringToFront(_ g: AgentGroup) {
        var cur = g.rootPID
        var hops = 0
        while hops < 16, cur > 1 {
            if let app = NSRunningApplication(processIdentifier: cur), app.activationPolicy == .regular {
                app.activate(options: [.activateAllWindows])
                return
            }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(cur, PROC_PIDTBSDINFO, 0, &info, size) == size else { return }
            cur = pid_t(bitPattern: info.pbi_ppid)
            hops += 1
        }
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
    }

    /// Claude 가 하나도 안 떠 있으면 「자는 클로드」 유령 칸을 하나 보여 준다 (휘두르면 깨움)
    private func withGhost(_ incoming: Snapshot) -> Snapshot {
        let claudeUp = incoming.groups.contains { ($0.kind == .claudeCode || $0.kind == .claudeApp) && $0.id != Self.ghostID }
        let force = ProcessInfo.processInfo.environment["WHIPLASH_GHOST"] != nil
        guard !claudeUp || force else { return incoming }
        var s = incoming
        s.groups.append(AgentGroup(id: Self.ghostID, kind: .claudeCode, label: t("꺼져 있어요"), rootPID: 0, start: 0))
        return s
    }

    /// 채찍 맞고 뛰는 보조 프로세스를 채찍 맞은 칸에 합친다: 그 칸이 일하는 것처럼 보이고, 보조 줄은 숨긴다
    private func merged(_ incoming: Snapshot) -> Snapshot {
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
