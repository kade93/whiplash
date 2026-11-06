import Foundation
import Darwin

// MARK: - 데이터

struct AgentGroup: Identifiable, Equatable {
    let id: String          // "cli:<pid>" 세션 하나, 또는 "app:<kind>" 앱 전체
    let kind: AgentKind
    let label: String       // 프로젝트 폴더 이름, 앱이면 "앱"
    let rootPID: pid_t
    let start: UInt64
    var dir: String? = nil  // 작업 폴더 전체 경로 (CLI만)
    var cpu: Double = 0      // 쓰는 코어 수 (1.0 = 코어 하나 꽉)
    var memory: UInt64 = 0   // 바이트 (활성 상태 보기의 '메모리'와 같은 값)
    var processCount: Int = 0
    var awake: Bool = false
    var session: AgentSession? = nil   // Claude Code 세션 정보 (있을 때만)
    var whipJob: WhipJob? = nil        // 채찍 맞고 하는 일 (보조 프로세스는 이 줄에 합쳐진다)

    /// 과부하: 코어 1.5개 넘게 쓰거나, 메모리를 2GB(또는 전체의 10%) 넘게 물고 있으면
    func overloaded(memTotal: UInt64) -> Bool {
        cpu >= 1.5 || memory >= max(2_147_483_648, memTotal / 10)
    }
}

struct Snapshot {
    var groups: [AgentGroup] = []
    var ncpu: Int = ProcessInfo.processInfo.activeProcessorCount
    var machineBusy: Double = 0                       // 맥 전체 CPU 0...1
    var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var memUsed: UInt64 = 0
    var selfCPU: Double = 0
    var selfMemory: UInt64 = 0

    var agentCPU: Double { groups.reduce(0.0) { $0 + $1.cpu } }
    var agentMemory: UInt64 { groups.reduce(UInt64(0)) { $0 + $1.memory } }

    struct KindTotal { let kind: AgentKind; let cpu: Double; let memory: UInt64 }

    var byKind: [KindTotal] {
        AgentKind.allCases.compactMap { k in
            let gs = groups.filter { $0.kind == k }
            guard !gs.isEmpty else { return nil }
            return KindTotal(kind: k,
                             cpu: gs.reduce(0.0) { $0 + $1.cpu },
                             memory: gs.reduce(UInt64(0)) { $0 + $1.memory })
        }
    }
}

struct StorageItem: Identifiable, Equatable {
    let kind: AgentKind
    let bytes: UInt64
    let paths: [String]
    var id: String { kind.rawValue }
}

struct DiskInfo: Equatable {
    var free: UInt64 = 0
    var total: UInt64 = 0
}

// MARK: - 어떤 프로세스가 어떤 에이전트인지
// 새 에이전트를 넣고 싶으면 여기에 한 줄 추가하면 된다.

enum AgentMatcher {
    static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]

    /// path: 실행 파일 전체 경로, name: 실행 파일 이름, args: (node·python일 때만) 명령줄 전체
    static func match(path: String, name: String, args: String) -> (kind: AgentKind, isApp: Bool)? {
        // Claude Code (단독 설치·npm·IDE 확장·Claude 앱 안에서 실행된 것 모두)
        if path.contains("claude-code") || path.contains("/claude/versions/")
            || args.contains("@anthropic-ai/claude-code") || args.contains("/bin/claude ") || args.hasSuffix("/bin/claude") {
            return (.claudeCode, false)
        }
        if path.contains("/Claude.app/") { return (.claudeApp, true) }
        if name == "claude" { return (.claudeCode, false) }

        if path.contains("/Codex.app/") { return (.codex, true) }
        if name == "codex" || name.hasPrefix("codex-") || path.contains("@openai/codex")
            || args.contains("@openai/codex") || args.contains("/bin/codex") {
            return (.codex, false)
        }

        if path.contains("/Cursor.app/") { return (.cursor, true) }
        if name == "cursor-agent" || args.contains("cursor-agent") { return (.cursor, false) }

        if path.contains("/Antigravity.app/") { return (.antigravity, true) }

        if name == "gemini" || args.contains("@google/gemini-cli") || args.contains("/bin/gemini") {
            return (.gemini, false)
        }

        let others: Set<String> = ["opencode", "aider", "goose", "amp", "crush", "qwen"]
        if others.contains(name) || args.contains("/bin/aider") || args.contains("/bin/amp")
            || args.contains("opencode") || args.contains("@qwen-code") {
            return (.other, false)
        }
        return nil
    }
}

// MARK: - 프로세스 측정 (자체 큐에서만 부른다)

final class ProcessSampler {
    private struct Key: Hashable { let pid: pid_t; let start: UInt64 }
    private struct Meta { let kind: AgentKind?; let isApp: Bool }

    private var metaCache: [Key: Meta] = [:]
    private var labelCache: [Key: (label: String, dir: String?)] = [:]
    private var lastCPU: [Key: UInt64] = [:]
    private var lastWall: UInt64 = 0
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private let numer: UInt64
    private let denom: UInt64
    private let host = mach_host_self()
    private let uid = getuid()
    private let home = NSHomeDirectory()

    init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        numer = UInt64(max(tb.numer, 1))
        denom = UInt64(max(tb.denom, 1))
    }

    func sample() -> Snapshot {
        let now = DispatchTime.now().uptimeNanoseconds
        let wall: UInt64 = lastWall == 0 ? 0 : now &- lastWall
        lastWall = now

        // 1) 내 계정의 프로세스 목록과 부모 관계
        var parent: [pid_t: pid_t] = [:]
        var keyOf: [pid_t: Key] = [:]
        var metaOf: [pid_t: Meta] = [:]
        for p in listProcesses() where p.pid > 0 && p.uid == uid {
            let key = Key(pid: p.pid, start: p.start)
            parent[p.pid] = p.ppid
            keyOf[p.pid] = key
            if let m = metaCache[key] {
                metaOf[p.pid] = m
            } else {
                let m = classify(pid: p.pid, comm: p.comm)
                metaCache[key] = m
                metaOf[p.pid] = m
            }
        }

        // 2) 각 프로세스를 가장 가까운 에이전트 조상에게 붙인다 (하위 셸·MCP 서버·빌드도 포함)
        var memo: [pid_t: String?] = [:]
        var groupInfo: [String: (kind: AgentKind, root: pid_t)] = [:]

        func groupKey(_ pid: pid_t) -> String? {
            var chain: [pid_t] = []
            var cur = pid
            var result: String? = nil
            while chain.count < 128 {
                if let known = memo[cur] { result = known; break }
                chain.append(cur)
                if let m = metaOf[cur], let kind = m.kind {
                    if m.isApp {
                        let k = "app:" + kind.rawValue
                        if groupInfo[k] == nil { groupInfo[k] = (kind, cur) }
                        result = k
                    } else {
                        var root = cur
                        var hops = 0
                        while hops < 64, let p = parent[root], p > 1, p != root,
                              let pm = metaOf[p], pm.kind == kind, !pm.isApp {
                            root = p
                            hops += 1
                        }
                        let k = "cli:\(root)"
                        groupInfo[k] = (kind, root)
                        result = k
                    }
                    break
                }
                guard let p = parent[cur], p > 1, p != cur, metaOf[p] != nil else { break }
                cur = p
            }
            for c in chain { memo[c] = .some(result) }
            return result
        }

        // 3) CPU·메모리 합산
        var acc: [String: AgentGroup] = [:]
        var newCPU: [Key: UInt64] = [:]
        var snap = Snapshot()
        let me = getpid()

        for (pid, key) in keyOf {
            let gk = groupKey(pid)
            if gk == nil && pid != me { continue }
            guard let u = usage(pid) else { continue }

            let cpuNs = u.cpuNs
            newCPU[key] = cpuNs
            var cores = 0.0
            if wall > 0, let prev = lastCPU[key], cpuNs >= prev {
                cores = Double(cpuNs - prev) / Double(wall)
            }

            if pid == me {
                snap.selfCPU = cores
                snap.selfMemory = u.memory
                continue
            }
            guard let k = gk, let gi = groupInfo[k] else { continue }
            var g: AgentGroup
            if let existing = acc[k] {
                g = existing
            } else {
                let ld = label(root: gi.root, key: keyOf[gi.root], isApp: k.hasPrefix("app:"))
                g = AgentGroup(id: k, kind: gi.kind, label: ld.label,
                               rootPID: gi.root, start: keyOf[gi.root]?.start ?? 0, dir: ld.dir)
            }
            g.cpu += cores
            g.memory += u.memory
            g.processCount += 1
            acc[k] = g
        }
        lastCPU = newCPU

        let live = Set(keyOf.values)
        metaCache = metaCache.filter { live.contains($0.key) }
        labelCache = labelCache.filter { live.contains($0.key) }

        snap.groups = acc.values.sorted { a, b in
            a.kind.order != b.kind.order ? a.kind.order < b.kind.order : a.start < b.start
        }
        snap.machineBusy = machineBusy()
        snap.memUsed = memoryUsed()
        return snap
    }

    // MARK: 시스템 호출 도우미

    /// 전체 프로세스 목록 (sysctl: 앱 샌드박스 안에서도 읽힌다. proc_listallpids 는 막힘)
    private func listProcesses() -> [(pid: pid_t, ppid: pid_t, uid: uid_t, start: UInt64, comm: String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        var sz = buf.count * stride
        guard sysctl(&mib, 4, &buf, &sz, nil, 0) == 0 else { return [] }
        return buf.prefix(sz / stride).map { kp in
            let tv = kp.kp_proc.p_starttime
            return (kp.kp_proc.p_pid, kp.kp_eproc.e_ppid, kp.kp_eproc.e_ucred.cr_uid,
                    UInt64(max(tv.tv_sec, 0)) &* 1_000_000 &+ UInt64(max(tv.tv_usec, 0)), tupleString(kp.kp_proc.p_comm))
        }
    }

    /// CPU 누적(ns)·메모리. rusage(정확: phys footprint)가 막히면 taskinfo(resident)로.
    private func usage(_ pid: pid_t) -> (cpuNs: UInt64, memory: UInt64)? {
        if let ru = rusage(pid) {
            return ((ru.ri_user_time &+ ru.ri_system_time) &* numer / denom, ru.ri_phys_footprint)
        }
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size else { return nil }
        return ((ti.pti_total_user &+ ti.pti_total_system) &* numer / denom, ti.pti_resident_size)
    }

    private func classify(pid: pid_t, comm: String) -> Meta {
        let path = execPath(pid) ?? ""
        let base = (path as NSString).lastPathComponent
        let name = base.isEmpty ? comm : base
        var args = ""
        if AgentMatcher.interpreters.contains(name) || name.hasPrefix("python") {
            args = arguments(pid) ?? ""
        }
        if let m = AgentMatcher.match(path: path, name: name, args: args) {
            return Meta(kind: m.kind, isApp: m.isApp)
        }
        return Meta(kind: nil, isApp: false)
    }

    private func execPath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// node·python으로 도는 CLI는 실행 파일이 node라서 명령줄을 봐야 한다
    private func arguments(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }    // 실행 경로 건너뛰기
        while i < size && buf[i] == 0 { i += 1 }
        var parts: [String] = []
        var start = i
        while i < size && parts.count < argc {
            if buf[i] == 0 {
                parts.append(String(decoding: buf[start..<i], as: UTF8.self))
                start = i + 1
            }
            i += 1
        }
        return parts.joined(separator: " ")
    }

    private func rusage(_ pid: pid_t) -> rusage_info_v2? {
        var info = rusage_info_v2()
        let r = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return r == 0 ? info : nil
    }

    private func label(root: pid_t, key: Key?, isApp: Bool) -> (label: String, dir: String?) {
        if isApp { return (t("앱"), nil) }
        guard let key = key else { return ("", nil) }
        if let cached = labelCache[key] { return cached }
        var l = t("터미널")
        let dir = cwd(root)
        if let dir = dir {
            if dir == home { l = "~" }
            else if dir == "/" { l = "/" }
            else { l = (dir as NSString).lastPathComponent }
        }
        labelCache[key] = (l, dir)
        return (l, dir)
    }

    private func cwd(_ pid: pid_t) -> String? {
        var vpi = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, size) == size else { return nil }
        let path = tupleString(vpi.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    private func machineBusy() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total, busy >= last.busy else { return 0 }
        return min(1, Double(busy - last.busy) / Double(total - last.total))
    }

    /// 활성 상태 보기의 '사용된 메모리'와 같은 계산 (앱 메모리 + 와이어드 + 압축)
    private func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }
}

/// C 구조체의 char 배열(튜플)을 문자열로
func tupleString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

// MARK: - 저장공간 (30분에 한 번, 가장 낮은 우선순위로)

enum StorageScanner {
    static func folders(_ kind: AgentKind) -> [String] {
        let h = Paths.home
        let sup = h + "/Library/Application Support"
        switch kind {
        case .claudeCode:  return [h + "/.claude"]
        case .claudeApp:   return [sup + "/Claude"]
        case .codex:       return [h + "/.codex"]
        case .cursor:      return [h + "/.cursor", sup + "/Cursor"]
        case .gemini:      return [h + "/.gemini"]
        case .antigravity: return [h + "/.antigravity", sup + "/Antigravity"]
        case .other:       return []
        }
    }

    static func scan() -> [StorageItem] {
        AgentKind.allCases.compactMap { kind in
            let paths = folders(kind).filter { FileManager.default.fileExists(atPath: $0) }
            guard !paths.isEmpty else { return nil }
            let total = paths.reduce(UInt64(0)) { $0 + size(of: $1) }
            return total > 0 ? StorageItem(kind: kind, bytes: total, paths: paths) : nil
        }
    }

    static func size(of path: String) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys,
            options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        let keySet = Set(keys)
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keySet), v.isRegularFile == true else { continue }
            total += UInt64(max(v.totalFileAllocatedSize ?? 0, 0))
        }
        return total
    }

    static func disk() -> DiskInfo {
        let url = URL(fileURLWithPath: Paths.home)
        guard let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                        .volumeTotalCapacityKey]) else { return DiskInfo() }
        let free = max(v.volumeAvailableCapacityForImportantUsage ?? 0, 0)
        let total = max(v.volumeTotalCapacity ?? 0, 0)
        return DiskInfo(free: UInt64(free), total: UInt64(total))
    }
}


// MARK: - 개발용: 샌드박스에서 어떤 프로세스 API가 되는지 로그
enum ProcessProbe {
    static func log() {
        let n = proc_listallpids(nil, 0)
        NSLog("PROBE proc_listallpids count=%d", n)
        var pids = [pid_t](repeating: 0, count: Int(max(n, 1)) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        NSLog("PROBE proc_listallpids got=%d first=%@", got, Array(pids.prefix(5)).map(String.init).joined(separator: ","))

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        let r = sysctl(&mib, 4, nil, &size, nil, 0)
        NSLog("PROBE sysctl kern.proc.all r=%d bytes=%d procs=%d errno=%d", r, size, size / MemoryLayout<kinfo_proc>.size, errno)
        if r == 0, size > 0 {
            var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.size + 8)
            var sz = buf.count * MemoryLayout<kinfo_proc>.size
            if sysctl(&mib, 4, &buf, &sz, nil, 0) == 0 {
                let cnt = sz / MemoryLayout<kinfo_proc>.size
                let sample = buf.prefix(cnt).prefix(200).filter { tupleString($0.kp_proc.p_comm).contains("claude") }
                NSLog("PROBE sysctl procs=%d claude-ish=%@", cnt, sample.map { "\($0.kp_proc.p_pid):\(tupleString($0.kp_proc.p_comm))" }.joined(separator: " "))
            }
        }
        let me = getpid()
        var info = proc_bsdinfo()
        let ok = proc_pidinfo(me, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        NSLog("PROBE proc_pidinfo(self)=%d errno=%d", ok, errno)
        var other = proc_bsdinfo()
        let ok2 = proc_pidinfo(1, PROC_PIDTBSDINFO, 0, &other, Int32(MemoryLayout<proc_bsdinfo>.size))
        NSLog("PROBE proc_pidinfo(launchd)=%d errno=%d", ok2, errno)
        var ru = rusage_info_v2()
        let ok3 = withUnsafeMutablePointer(to: &ru) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(me, RUSAGE_INFO_V2, $0) }
        }
        NSLog("PROBE proc_pid_rusage(self)=%d footprint=%llu", ok3, ru.ri_phys_footprint)
        var buf = [CChar](repeating: 0, count: 4096)
        let pl = proc_pidpath(1, &buf, UInt32(buf.count))
        NSLog("PROBE proc_pidpath(launchd)=%d errno=%d", pl, errno)
        var vpi = proc_vnodepathinfo()
        let cw = proc_pidinfo(me, PROC_PIDVNODEPATHINFO, 0, &vpi, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        NSLog("PROBE cwd(self)=%d", cw)
        // 남의 프로세스: 부모(launchd 1)와 claude 하나
        var ru2 = rusage_info_v2()
        let ok4 = withUnsafeMutablePointer(to: &ru2) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(1, RUSAGE_INFO_V2, $0) }
        }
        NSLog("PROBE proc_pid_rusage(launchd)=%d errno=%d footprint=%llu", ok4, errno, ru2.ri_phys_footprint)
        let ppid = getppid()
        var ru3 = rusage_info_v2()
        let ok5 = withUnsafeMutablePointer(to: &ru3) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(ppid, RUSAGE_INFO_V2, $0) }
        }
        NSLog("PROBE proc_pid_rusage(parent %d)=%d errno=%d footprint=%llu", ppid, ok5, errno, ru3.ri_phys_footprint)
        var mib2: [Int32] = [CTL_KERN, KERN_PROCARGS2, ppid]
        var sz2 = 0
        let r2 = sysctl(&mib2, 3, nil, &sz2, nil, 0)
        NSLog("PROBE procargs2(parent)=%d bytes=%d errno=%d", r2, sz2, errno)
        var vpi2 = proc_vnodepathinfo()
        let cw2 = proc_pidinfo(ppid, PROC_PIDVNODEPATHINFO, 0, &vpi2, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        NSLog("PROBE cwd(parent)=%d errno=%d", cw2, errno)
        var host = host_cpu_load_info()
        var cnt = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &host) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(cnt)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cnt) }
        }
        NSLog("PROBE host_statistics=%d", kr)
        var ti = proc_taskinfo()
        let tk = proc_pidinfo(ppid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size))
        NSLog("PROBE taskinfo(parent)=%d resident=%llu user=%llu", tk, ti.pti_resident_size, ti.pti_total_user)
    }
}
