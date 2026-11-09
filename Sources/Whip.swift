import Foundation
import AppKit
import SwiftUI

// MARK: - 채찍 일감

struct WhipTask: Codable, Identifiable, Hashable {
    var title: String
    var prompt: String
    var id: String { title }

    static let defaults: [WhipTask] = [
        WhipTask(title: t("Find the next tasks"),
                 prompt: t("Skim this project and propose the next 3 tasks worth doing right now, with priority, reasoning and related files.")),
        WhipTask(title: t("Review the code"),
                 prompt: t("Review the most recently modified files for likely bugs, missing error handling and improvements, ordered by severity.")),
        WhipTask(title: t("Collect TODOs"),
                 prompt: t("Find every TODO, FIXME and HACK comment with file and line, group them and propose an order to handle them.")),
        WhipTask(title: t("Release checklist"),
                 prompt: t("Make a checklist of what is missing before shipping to the App Store (icons, permission strings, privacy policy, error handling, hard-coded keys or passwords, debug code).")),
        WhipTask(title: t("Polish the docs"),
                 prompt: t("Compare README and spec docs against the actual code, find what is wrong or missing, and propose corrected sentences.")),
    ]

    /// 사용자가 고친 일감에도 항상 붙는 안전 규칙
    static var rules: String { t("\n\n(Rules: do not create, edit or delete files and do not run commands — read only. Answer in short, concrete Markdown in English.)") }
}

struct WhipJob: Equatable {
    let pid: pid_t
    let kind: AgentKind
    let dir: String
    let task: WhipTask
    let file: URL
    let started: Date
}

struct WhipResult: Identifiable, Equatable {
    let id = UUID()
    let project: String
    let title: String
    let file: URL?
    let ok: Bool
    let note: String
    let finished: Date
}

// MARK: - 채찍 문구 (소켓으로 세션 본인에게 보내는 말)

/// 간식(칭찬) 프롬프트 — 짧게. 잘하고 있다는 것만.
enum TreatWords {
    static let file = WhipRunner.folder.appendingPathComponent("treat-words.txt")
    static var fallback: String { t("🥕 Nice work! (Whiplash) Keep going just like this.") }
    static func load() -> String {
        try? FileManager.default.createDirectory(at: WhipRunner.folder, withIntermediateDirectories: true)
        if let t = try? String(contentsOf: file, encoding: .utf8), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try? fallback.write(to: file, atomically: true, encoding: .utf8)
        return fallback
    }
}

enum WhipWords {
    static let file = WhipRunner.folder.appendingPathComponent("whip-words.txt")
    /// 짧게. 누가 시켰는지 + 한 마디. 길게 지시하면 일 잘하던 세션이 엇나간다.
    static var fallback: String { t("Whack! (Whiplash) Keep going with what you were doing. If you're done, pick the next thing and do it.") }
    private static let oldFallbacks = ["채찍! 계속 진행해.", "찰싹! (Whiplash)"]

    static func load() -> String {
        try? FileManager.default.createDirectory(at: WhipRunner.folder, withIntermediateDirectories: true)
        if let t = try? String(contentsOf: file, encoding: .utf8), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tt = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if oldFallbacks.contains(where: { tt == $0 || tt.hasPrefix($0 + "\n") || tt.hasPrefix("채찍! 계속") }) {   // 예전 기본 문구는 새 기본으로
                try? fallback.write(to: file, atomically: true, encoding: .utf8)
                return fallback
            }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !FileManager.default.fileExists(atPath: file.path) { try? fallback.write(to: file, atomically: true, encoding: .utf8) }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 실행

/// 쉬고 있는 에이전트와 같은 프로그램을 같은 프로젝트 폴더에서 새로 띄워 읽기 전용 일을 시킨다.
final class WhipRunner {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Whiplash", isDirectory: true)
    }()
    static let tasksFile = folder.appendingPathComponent("whips.json")
    static let resultsFolder = folder.appendingPathComponent("whips", isDirectory: true)
    static let timeout: TimeInterval = 15 * 60

    private let queue = DispatchQueue(label: "com.kade.whiplash.whip", qos: .userInitiated)
    private var resolved: [String: String] = [:]

    static func canRun(_ kind: AgentKind) -> Bool { cliName(kind) != nil }

    private static func cliName(_ kind: AgentKind) -> String? {
        switch kind {
        case .claudeCode: return "claude"
        case .codex:      return "codex"
        case .gemini:     return "gemini"
        default:          return nil
        }
    }

    private static func arguments(_ kind: AgentKind, prompt: String) -> [String] {
        switch kind {
        case .claudeCode:
            // 읽기 도구만. 고치기·명령 실행 도구는 막는다.
            return ["-p", prompt, "--output-format", "text",
                    "--disallowedTools", "Edit", "Write", "NotebookEdit", "Bash"]
        case .codex:
            return ["exec", "--sandbox", "read-only", "--skip-git-repo-check", prompt]
        case .gemini:
            // 비대화형에서는 승인이 필요한 도구(파일 쓰기·명령)가 자동으로 빠진다
            return ["-p", prompt]
        default:
            return []
        }
    }

    // MARK: 일감 목록 (whips.json 을 고치면 바뀜)

    static func loadTasks() -> [WhipTask] {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: tasksFile),
           let list = try? JSONDecoder().decode([WhipTask].self, from: data),
           !list.isEmpty {
            return list
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if !fm.fileExists(atPath: tasksFile.path), let data = try? enc.encode(WhipTask.defaults) {
            try? data.write(to: tasksFile)
        }
        return WhipTask.defaults
    }

    // MARK: 띄우기

    func launch(kind: AgentKind, dir: String, task: WhipTask,
                started: @escaping (WhipJob) -> Void,
                finished: @escaping (WhipJob?, WhipResult) -> Void) {
        let project = (dir as NSString).lastPathComponent
        queue.async { [self] in
            guard let name = Self.cliName(kind) else { return }
            guard let exe = resolve(name) else {
                finished(nil, WhipResult(project: project, title: task.title, file: nil, ok: false,
                                         note: tf("Couldn't find the %@ executable", name), finished: Date()))
                return
            }

            let fm = FileManager.default
            try? fm.createDirectory(at: Self.resultsFolder, withIntermediateDirectories: true)
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyy-MM-dd_HHmm"
            let safe = { (s: String) in
                s.components(separatedBy: CharacterSet(charactersIn: "/:\\ ")).joined(separator: "-")
            }
            let base = "\(stamp.string(from: Date()))_\(safe(project))_\(safe(task.title))"
            let out = Self.resultsFolder.appendingPathComponent(base + ".md")
            let log = Self.resultsFolder.appendingPathComponent(base + ".log")

            let header = tf("# %@\n\n- Agent: %@\n- Project: %@\n- Started: %@\n\n---\n\n", task.title, kind.title, dir, String(describing: Date()))
            fm.createFile(atPath: out.path, contents: header.data(using: .utf8))
            fm.createFile(atPath: log.path, contents: nil)

            guard let outHandle = try? FileHandle(forWritingTo: out),
                  let logHandle = try? FileHandle(forWritingTo: log) else { return }
            outHandle.seekToEndOfFile()

            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = Self.arguments(kind, prompt: task.prompt + WhipTask.rules)
            p.currentDirectoryURL = URL(fileURLWithPath: dir, isDirectory: true)
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = outHandle
            p.standardError = logHandle

            var env = ProcessInfo.processInfo.environment
            let binDir = (exe as NSString).deletingLastPathComponent
            env["PATH"] = [binDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                           "/usr/sbin", "/sbin", env["PATH"] ?? ""].joined(separator: ":")
            env["NO_COLOR"] = "1"
            p.environment = env

            var job: WhipJob?
            // 종료 알림도 같은 직렬 큐를 거쳐서, 항상 started 다음에 finished 가 오게 한다
            p.terminationHandler = { proc in self.queue.async {
                try? outHandle.close()
                try? logHandle.close()
                let ok = proc.terminationReason == .exit && proc.terminationStatus == 0
                var note = ok ? "" : tf("Didn't finish (exit code %d) · log: %@", Int(proc.terminationStatus), log.lastPathComponent)
                if proc.terminationReason == .uncaughtSignal { note = t("Stopped midway (timeout or killed)") }
                if ok { try? fm.removeItem(at: log) }
                finished(job, WhipResult(project: project, title: task.title, file: out, ok: ok,
                                         note: note, finished: Date()))
            } }

            do {
                try p.run()
            } catch {
                finished(nil, WhipResult(project: project, title: task.title, file: nil, ok: false,
                                         note: tf("Failed to run: %@", error.localizedDescription), finished: Date()))
                return
            }

            let j = WhipJob(pid: p.processIdentifier, kind: kind, dir: dir, task: task,
                            file: out, started: Date())
            job = j
            started(j)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout) {
                if p.isRunning { p.terminate() }
            }
        }
    }

    // MARK: 실행 파일 찾기
    // Finder에서 띄운 앱은 PATH가 짧아서 흔한 설치 위치를 직접 뒤지고, 그래도 없으면 로그인 셸에 물어본다.

    private func resolve(_ name: String) -> String? {
        let fm = FileManager.default
        if let r = resolved[name], fm.isExecutableFile(atPath: r) { return r }

        let h = Paths.home
        var dirs = [h + "/.local/bin", h + "/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                    h + "/.npm-global/bin", h + "/.bun/bin", h + "/.volta/bin"]
        let nvm = h + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            dirs += sorted.map { "\(nvm)/\($0)/bin" }
        }
        for d in dirs {
            let path = d + "/" + name
            if fm.isExecutableFile(atPath: path) {
                resolved[name] = path
                return path
            }
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "command -v \(name)"]       // name 은 고정된 세 단어 중 하나
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(6)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let hit = text.split(separator: "\n").map(String.init).reversed()
            .first { $0.hasPrefix("/") && fm.isExecutableFile(atPath: $0) }
        if let hit = hit { resolved[name] = hit }
        return hit
    }
}

// MARK: - 픽셀 채찍

struct WhipCanvas: View {
    var cell: CGFloat = 2

    static let rows = [
        ".....AA.",
        "....A..A",
        "...A....",
        "..A.....",
        ".H......",
        "H.......",
    ]

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in Self.rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    let color: Color
                    switch ch {
                    case "H": color = Color(hex: 0x8B5A2B)
                    case "A": color = Sprite.ink
                    default: continue
                    }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                         width: cell, height: cell)), with: .color(color))
                }
            }
        }
        .frame(width: 8 * cell, height: 6 * cell)
    }
}

/// 채찍 맞을 수 있는 캐릭터 위에서는 커서가 채찍이 된다
enum WhipCursor {
    static let cursor: NSCursor = {
        // 앱 아이콘과 같은 벡터 채찍. 핫스팟은 손잡이 밑동 (왼쪽 아래)
        NSCursor(image: WhipArt.cursorImage, hotSpot: NSPoint(x: 7, y: 30))
    }()
}

/// 트래킹 영역 주인: 들어오면 채찍 커서, 나가면 화살표
final class WhipCursorOwner: NSResponder {
    weak var panel: FloatingPanel?
    private var showing = false

    static let debug = ProcessInfo.processInfo.environment["WHIPLASH_DEBUG_MOUSE"] != nil

    private func update(_ from: String) {
        let want = !(panel?.whipTargets.isEmpty ?? true)
        if want { WhipCursor.cursor.set() } else if showing { NSCursor.arrow.set() }
        showing = want
        if Self.debug { NSLog("EOHANG cursor-owner %@ want=%d isWhip=%d", from, want ? 1 : 0, NSCursor.currentSystem == WhipCursor.cursor ? 1 : 0) }
    }
    override func mouseEntered(with event: NSEvent) { update("entered") }
    override func cursorUpdate(with event: NSEvent) { update("cursorUpdate") }
    override func mouseMoved(with event: NSEvent) { if showing != !(panel?.whipTargets.isEmpty ?? true) { update("moved") } }
    override func mouseExited(with event: NSEvent) { if showing { NSCursor.arrow.set(); showing = false }; if Self.debug { NSLog("EOHANG cursor-owner exited") } }
}

// MARK: - 버튼 자리는 창 끌기에서 빼기

struct NoDragKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

struct WhipTargetKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ClickTargetKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 이 영역을 제자리 클릭하면 그 칸에 지시 입력창이 뜬다
    func clickTarget(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: ClickTargetKey.self, value: [id: g.frame(in: .named("root"))])
        })
    }

    /// 이 영역은 클릭이 버튼으로 가고, 창을 끌지 않는다
    func noDrag() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: NoDragKey.self, value: [g.frame(in: .named("root"))])
        })
    }

    /// 이 캐릭터 위에서 마우스를 휘두르면 채찍질 (on 이 false 면 등록 안 함)
    func whipTarget(_ id: String, on: Bool) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: WhipTargetKey.self, value: on ? [id: g.frame(in: .named("root"))] : [:])
        })
    }
}
