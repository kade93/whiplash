import Foundation
import AppKit

// MARK: - 경로 (앱스토어 샌드박스에서는 홈 폴더를 한 번 허락받아 북마크로 연다)

enum Paths {
    static let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    /// 전체 기능판(공증 직접 배포) 내려받는 곳. 앱스토어판 메뉴·입력창에서 연다.
    static let fullEditionURL = URL(string: "https://github.com/kade93/whiplash/releases/latest")!
    static func openFullEdition() { NSWorkspace.shared.open(fullEditionURL) }
    private static let bookmarkKey = "homeBookmark"
    private static var granted: URL? = {
        guard sandboxed, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
                                 bookmarkDataIsStale: &stale), !stale else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }()

    /// 진짜 홈 폴더 (샌드박스 밖이면 NSHomeDirectory, 안이면 허락받은 폴더, 못 받았으면 컨테이너)
    static var home: String { granted?.path ?? NSHomeDirectory() }
    static var hasHomeAccess: Bool { !sandboxed || granted != nil }
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    /// 홈 폴더 고르기 창. 고르면 북마크로 저장해 다음부터는 안 묻는다.
    static func requestHomeAccess() {
        let panel = NSOpenPanel()
        panel.message = t("Claude Code 세션 정보(~/.claude)를 읽으려면 홈 폴더 접근을 허용해 주세요. 읽기만 해요.")
        panel.prompt = t("허용")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: realHome)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        granted?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        granted = url
    }
}

// MARK: - Claude Code 세션 정보
// Claude Code는 살아 있는 동안 ~/.claude/sessions/<pid>.json 에 제목·상태를, 
// ~/.claude/projects/<폴더>/<세션>.jsonl 에 대화 기록을 남긴다. 둘 다 읽기만 한다.

/// 캐릭터가 들고 있을 연장 = 지금 하는 일
enum Chore: Equatable {
    case none
    case read      // 책
    case write     // 연필
    case run       // 망치
    case search    // 돋보기
    case delegate  // 채찍 (부하를 시킴)
    case web       // 지구본
    case think     // 생각 풍선
    case answer    // 말풍선
    case strike    // 피켓 (파업)

    static func of(tool: String) -> Chore {
        switch tool {
        case "Read", "NotebookRead":                          return .read
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "TodoWrite": return .write
        case "Bash", "BashOutput", "KillShell":              return .run
        case "Grep", "Glob", "LS":                            return .search
        case "Agent", "Task":                                 return .delegate
        case "WebSearch", "WebFetch":                         return .web
        case "AskUserQuestion", "ExitPlanMode":               return .answer
        default:                                              return tool.hasPrefix("mcp__") ? .web : .run
        }
    }
}

struct AgentSession: Equatable {
    enum Status: String { case busy, idle, unknown }

    /// 쉬는 중일 때 무엇을 기다리나
    enum Waiting: Equatable {
        case none
        case reply        // 답을 하고 멈춤 → 내 차례
        case question     // 질문(AskUserQuestion)·계획 승인을 기다림
        case permission   // 도구를 쓰려다 멈춤 → 허락 기다리는 듯
    }

    let pid: pid_t
    let sessionId: String
    let cwd: String
    var name: String
    var status: Status
    var startedAt: Date?
    var statusSince: Date?
    var entrypoint: String
    var socketPath: String? = nil    // /tmp/cc-socks/<pid>.sock
    var keyFile: URL? = nil          // ~/.claude/sessions/<pid>.<hash>.key (peerToken)

    // 기록 파일에서 (없으면 비어 있음)
    var lastPrompt = ""
    var lastReply = ""         // 마지막으로 한 말 (끝부분) — "…할까요?"
    var question = ""          // AskUserQuestion·계획 승인으로 물어본 것
    var options: [String] = [] // 그 질문의 선택지
    var activity = ""          // "실행 중 · 세션 상태 확인"
    var chore: Chore = .none
    var waiting: Waiting = .none
    var costUSD = 0.0
    var tokens = 0             // 세션 누적 토큰 (입력+출력+캐시 쓰기, 캐시 읽기 제외)
    var linesAdded = 0
    var linesRemoved = 0
    var transcript: URL? = nil
    var strikeUntil: Date? = nil      // 쿼터 바닥(429) → 파업. 리셋 시각을 모르면 1시간
    var onStrike: Bool { strikeUntil.map { $0 > Date() } ?? false }

    var needsYou: Bool { status == .idle && waiting != .none }
    var isDesktop: Bool { entrypoint == "claude-desktop" }
}

final class SessionReader {
    static var claudeDir: URL { URL(fileURLWithPath: Paths.home).appendingPathComponent(".claude", isDirectory: true) }
    static var sessionsDir: URL { claudeDir.appendingPathComponent("sessions", isDirectory: true) }
    static var projectsDir: URL { claudeDir.appendingPathComponent("projects", isDirectory: true) }

    private struct Tail {
        var size: UInt64 = 0
        var lastPrompt = ""
        var lastReply = ""
        var question = ""
        var options: [String] = []
        var aiTitle = ""
        var activity = ""
        var chore: Chore = .none
        var waiting: AgentSession.Waiting = .none
        var cost = 0.0
        var tokens = 0
        var added = 0
        var removed = 0
        var strikeUntil: Date? = nil
    }

    private var tails: [String: Tail] = [:]
    private var transcripts: [String: URL?] = [:]
    private let fm = FileManager.default

    /// 살아 있는 Claude Code 루트 PID들의 세션 정보
    func read(pids: [pid_t], starts: [pid_t: UInt64]) -> [pid_t: AgentSession] {
        var out: [pid_t: AgentSession] = [:]
        var liveIds: Set<String> = []
        for pid in pids {
            let url = Self.sessionsDir.appendingPathComponent("\(pid).json")
            guard let data = try? Data(contentsOf: url),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let sid = j["sessionId"] as? String,
                  let cwd = j["cwd"] as? String else { continue }

            // 재부팅 전 같은 PID가 남긴 낡은 파일은 건너뛴다
            let startedMs = (j["startedAt"] as? Double) ?? 0
            if let procStartUs = starts[pid], startedMs > 0,
               Double(procStartUs) / 1000 - startedMs > 10 * 60 * 1000 { continue }

            var s = AgentSession(
                pid: pid, sessionId: sid, cwd: cwd,
                name: (j["name"] as? String) ?? "",
                status: AgentSession.Status(rawValue: (j["status"] as? String) ?? "") ?? .unknown,
                startedAt: startedMs > 0 ? Date(timeIntervalSince1970: startedMs / 1000) : nil,
                statusSince: (j["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                entrypoint: (j["entrypoint"] as? String) ?? "")
            liveIds.insert(sid)
            s.socketPath = j["messagingSocketPath"] as? String
            if let names = try? fm.contentsOfDirectory(atPath: Self.sessionsDir.path),
               let k = names.first(where: { $0.hasPrefix("\(pid).") && $0.hasSuffix(".key") }) {
                s.keyFile = Self.sessionsDir.appendingPathComponent(k)
            }

            if let t = transcript(sessionId: sid, cwd: cwd) {
                s.transcript = t
                let tail = refreshTail(sessionId: sid, url: t)
                s.lastPrompt = tail.lastPrompt
                s.lastReply = tail.lastReply
                s.question = tail.question
                s.options = tail.options
                s.activity = tail.activity
                s.chore = tail.chore
                s.waiting = tail.waiting
                s.costUSD = tail.cost
                s.tokens = tail.tokens
                s.linesAdded = tail.added
                s.linesRemoved = tail.removed
                s.strikeUntil = tail.strikeUntil
                if s.name.isEmpty { s.name = tail.aiTitle }
            }
            out[pid] = s
        }
        tails = tails.filter { liveIds.contains($0.key) }
        transcripts = transcripts.filter { liveIds.contains($0.key) }
        return out
    }

    // MARK: 최근 프로젝트 (폴더 이름은 원래 경로를 못 되살리니 기록 첫머리의 cwd 를 읽는다)

    private var recentCache: (at: Date, dirs: [String])?

    func recentProjects(limit: Int = 8) -> [String] {
        if let c = recentCache, Date().timeIntervalSince(c.at) < 60 { return c.dirs }
        var found: [(String, Date)] = []
        if let dirs = try? fm.contentsOfDirectory(at: Self.projectsDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for d in dirs {
                guard let files = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                let jsonls = files.filter { $0.pathExtension == "jsonl" }
                guard let newest = jsonls.max(by: { (mtime($0) ?? .distantPast) < (mtime($1) ?? .distantPast) }),
                      let h = try? FileHandle(forReadingFrom: newest) else { continue }
                let head = String(decoding: (try? h.read(upToCount: 16 * 1024)) ?? Data(), as: UTF8.self)
                try? h.close()
                guard let r = head.range(of: "\"cwd\":\""), let end = head[r.upperBound...].firstIndex(of: "\"") else { continue }
                let cwd = String(head[r.upperBound..<end])
                if fm.fileExists(atPath: cwd), !found.contains(where: { $0.0 == cwd }) { found.append((cwd, mtime(newest) ?? .distantPast)) }
            }
        }
        let dirs = found.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
        recentCache = (Date(), dirs)
        return dirs
    }

    private func mtime(_ url: URL) -> Date? { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }

    // MARK: 기록 파일 찾기

    /// 폴더 경로의 글자·숫자 아닌 것을 전부 '-'로 바꾼 이름이 프로젝트 폴더
    static func encoded(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    private func transcript(sessionId: String, cwd: String) -> URL? {
        if let cached = transcripts[sessionId] { return cached }
        let name = sessionId + ".jsonl"
        var found: URL? = nil
        let direct = Self.projectsDir.appendingPathComponent(Self.encoded(cwd)).appendingPathComponent(name)
        if fm.fileExists(atPath: direct.path) {
            found = direct
        } else if let dirs = try? fm.contentsOfDirectory(at: Self.projectsDir, includingPropertiesForKeys: nil) {
            found = dirs.map { $0.appendingPathComponent(name) }.first { fm.fileExists(atPath: $0.path) }
        }
        transcripts[sessionId] = found
        return found
    }

    // MARK: 꼬리 읽기 (파일 크기가 바뀌었을 때만)

    private func refreshTail(sessionId: String, url: URL) -> Tail {
        var tail = tails[sessionId] ?? Tail()
        let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard size != tail.size else { return tail }
        let first = tails[sessionId] == nil
        let records = readRecords(url, size: size, bytes: first ? 512 * 1024 : 64 * 1024)
        tail.size = size
        Self.fold(records, into: &tail)
        tails[sessionId] = tail
        return tail
    }

    private func readRecords(_ url: URL, size: UInt64, bytes: Int) -> [[String: Any]] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard (try? h.seek(toOffset: offset)) != nil, let data = try? h.readToEnd() else { return [] }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }      // 중간에서 잘린 줄
        return lines.compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }

    /// 마지막 메시지가 무엇이었나
    private enum Last { case none, prompt, toolResult, text, tool(name: String, detail: String) }

    private static func fold(_ records: [[String: Any]], into tail: inout Tail) {
        var last = Last.none
        var touched = false
        for r in records {
            guard let type = r["type"] as? String else { continue }
            switch type {
            case "last-prompt":
                if let p = r["lastPrompt"] as? String { tail.lastPrompt = p }
            case "ai-title":
                if let t = r["aiTitle"] as? String { tail.aiTitle = t }
            case "system":
                // 쿼터 바닥: api_error 에 429 또는 rateLimits
                if (r["subtype"] as? String) == "api_error", let e = r["error"] as? [String: Any] {
                    let status = (e["status"] as? Int) ?? 0
                    let text = ((e["formatted"] as? String) ?? "").lowercased()
                    let limits = e["rateLimits"] as? [String: Any]
                    if status == 429 || limits != nil || text.contains("rate limit") || text.contains("usage limit") {
                        var until = Date().addingTimeInterval(3600)
                        if let l = limits {
                            if let n = (l["resetsAt"] as? Double) ?? (l["resets_at"] as? Double) {
                                until = Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
                            } else if let sec = (l["retryAfter"] as? Double) ?? (l["retry_after"] as? Double) {
                                until = Date().addingTimeInterval(sec)
                            }
                        }
                        if let ts = r["timestamp"] as? String, let when = ISO8601DateFormatter().date(from: ts),
                           Date().timeIntervalSince(when) > 6 * 3600 { break }      // 오래된 기록은 무시
                        tail.strikeUntil = until
                    }
                } else if (r["subtype"] as? String) != "api_error" {
                    break
                }
            case "cost-state":
                tail.cost = (r["totalCostUSD"] as? Double) ?? tail.cost
                if let mu = r["modelUsage"] as? [String: Any] {
                    var n = 0
                    for case let (_, u as [String: Any]) in mu {
                        for k in ["inputTokens", "outputTokens", "cacheCreationInputTokens"] { n += (u[k] as? Int) ?? Int((u[k] as? Double) ?? 0) }
                    }
                    if n > 0 { tail.tokens = n }
                }
                tail.added = (r["totalLinesAdded"] as? Int) ?? tail.added
                tail.removed = (r["totalLinesRemoved"] as? Int) ?? tail.removed
            case "assistant", "user":
                if (r["isSidechain"] as? Bool) == true || (r["isMeta"] as? Bool) == true { continue }
                guard let m = r["message"] as? [String: Any] else { continue }
                touched = true
                if type == "assistant" { tail.strikeUntil = nil }        // 답이 나오면 파업 끝
                if type == "user" {
                    if let blocks = m["content"] as? [[String: Any]],
                       blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                        last = .toolResult
                    } else {
                        last = .prompt
                        tail.lastReply = ""; tail.question = ""; tail.options = []      // 새 지시가 오면 지난 말은 끝
                    }
                } else if let blocks = m["content"] as? [[String: Any]] {
                    for b in blocks {
                        switch b["type"] as? String {
                        case "tool_use":
                            let name = (b["name"] as? String) ?? "?"
                            let input = b["input"] as? [String: Any] ?? [:]
                            last = .tool(name: name, detail: toolDetail(name, input))
                            if name == "AskUserQuestion", let qs = input["questions"] as? [[String: Any]], let q = qs.first {
                                tail.question = (q["question"] as? String) ?? ""
                                tail.options = ((q["options"] as? [[String: Any]]) ?? []).compactMap { $0["label"] as? String }
                            } else if name == "ExitPlanMode" {
                                tail.question = t("계획을 세웠어요. 이대로 진행할까요?")
                                tail.options = [t("진행해"), t("계획 고치자")]
                            } else {
                                tail.question = ""; tail.options = []
                            }
                        case "text":
                            if let t = b["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                last = .text
                                tail.lastReply = replyTail(t)
                            }
                        default: break
                        }
                    }
                }
            default: break
            }
        }
        guard touched else { return }
        switch last {
        case .none:
            tail.activity = ""; tail.waiting = .none; tail.chore = .none
        case .prompt:
            tail.activity = t("지시 읽는 중"); tail.waiting = .none; tail.chore = .read
        case .toolResult:
            tail.activity = t("생각하는 중"); tail.waiting = .none; tail.chore = .think
        case .text:
            tail.activity = t("답하는 중"); tail.waiting = .reply; tail.chore = .answer
        case .tool(let name, let detail):
            tail.activity = detail.isEmpty ? verb(name) : "\(verb(name)) · \(detail)"
            tail.waiting = ["AskUserQuestion", "ExitPlanMode"].contains(name) ? .question : .permission
            tail.chore = Chore.of(tool: name)
        }
    }

    /// 답의 끝부분만: 마지막 문단 (코드 블록·표 제외), 200자 안으로
    private static func replyTail(_ text: String) -> String {
        let paras = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") && !$0.hasPrefix("|") }
        guard var p = paras.last else { return "" }
        p = p.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " ")
        if p.hasPrefix("- ") || p.hasPrefix("* ") { p = String(p.dropFirst(2)) }
        return p.count > 200 ? "…" + String(p.suffix(200)) : p
    }

    // MARK: 도구 이름을 사람 말로

    private static func shortName(_ name: String) -> String {
        // mcp__server__tool → tool
        name.components(separatedBy: "__").last ?? name
    }

    private static func verb(_ name: String) -> String {
        switch name {
        case "Read":                      return t("읽는 중")
        case "Edit", "MultiEdit", "NotebookEdit": return t("고치는 중")
        case "Write":                     return t("쓰는 중")
        case "Bash":                      return t("실행 중")
        case "Grep", "Glob":              return t("찾는 중")
        case "Agent", "Task":             return t("부하 시키는 중")
        case "WebSearch":                 return t("검색 중")
        case "WebFetch":                  return t("웹 읽는 중")
        case "AskUserQuestion":           return t("물어보는 중")
        case "ExitPlanMode":              return t("계획 승인 기다림")
        case "TodoWrite":                 return t("할 일 적는 중")
        default:                          return shortName(name) + t(" 중")
        }
    }

    private static func toolDetail(_ name: String, _ input: [String: Any]) -> String {
        func file(_ k: String) -> String { (((input[k] as? String) ?? "") as NSString).lastPathComponent }
        let s: String
        switch name {
        case "Bash":
            s = (input["description"] as? String) ?? ((input["command"] as? String) ?? "")
        case "Read", "Edit", "MultiEdit", "Write", "NotebookEdit":
            s = file("file_path").isEmpty ? file("notebook_path") : file("file_path")
        case "Grep", "Glob":
            s = (input["pattern"] as? String) ?? ""
        case "Agent", "Task":
            s = (input["description"] as? String) ?? ""
        case "WebSearch":
            s = (input["query"] as? String) ?? ""
        case "WebFetch":
            s = URL(string: (input["url"] as? String) ?? "")?.host ?? ""
        case "AskUserQuestion", "ExitPlanMode":
            s = ""
        default:
            s = (input["description"] as? String) ?? (input["query"] as? String) ?? ""
        }
        let one = s.components(separatedBy: .newlines).first ?? s
        return one.count > 48 ? String(one.prefix(48)) + "…" : one
    }
}

// MARK: - 시간·돈 표시

func fmtAgo(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let s = Int(Date().timeIntervalSince(d))
    if s < 60 { return t("방금") }
    if s < 3600 { return tf("%d분", s / 60) }
    if s < 86400 { return tf("%d시간 %d분", s / 3600, s % 3600 / 60) }
    return tf("%d일", s / 86400)
}

/// 1.2M · 340k · 980
func fmtTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%dk", n / 1_000) }
    return String(n)
}

func fmtUSD(_ v: Double) -> String {
    if v <= 0 { return "" }
    if v < 1 { return String(format: "%.0f¢", v * 100) }
    if v < 100 { return String(format: "$%.1f", v) }
    return String(format: "$%.0f", v)
}
