import Foundation
import Network

/// One agent session as the Mac reports it ("list" reply: id, name, state, kind).
struct RemoteSession: Identifiable, Equatable {
    let id: String
    let name: String
    let state: String       // working / resting / waiting / strike
    let kind: String        // claudeCode, codex, cursor, gemini, antigravity, other
}

/// Finds every Mac running Whiplash on this network (they advertise _whiplash._udp) and sends one-line UDP commands
/// to all of them at once: "whipall", "whip", "whip <id>", "treatall", "treat <id>", "list", "flick <g>", "ping".
/// The Mac answers "ok …" / "err …" for actions and a multi-line "list" for the session list; both land in `lastReply` / `sessions`.
final class RemoteSender: ObservableObject {
    @Published var macName = ""             // names joined with " · "
    @Published var connected = false
    @Published var lastReply = ""           // last "ok …" / "err …" line from a Mac
    @Published var sessions: [RemoteSession] = []

    private var browser: NWBrowser?
    private var connections: [NWEndpoint: NWConnection] = [:]   // only touched on `queue`
    private var known: Set<NWEndpoint> = []                      // endpoints Bonjour currently advertises (on `queue`)
    private let queue = DispatchQueue(label: "com.kade.whiplash.remote.sender")
    private var listTimer: Timer?

    func start() {
        let b = NWBrowser(for: .bonjour(type: "_whiplash._udp", domain: nil), using: .udp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            let endpoints = Set(results.map { $0.endpoint })
            self.known = endpoints
            for (ep, c) in self.connections where !endpoints.contains(ep) { c.cancel(); self.connections[ep] = nil }
            for ep in endpoints where self.connections[ep] == nil { self.connect(to: ep) }
            let names = results.compactMap { r -> String? in if case .service(let n, _, _, _) = r.endpoint { return n } else { return nil } }.sorted()
            DispatchQueue.main.async { self.macName = names.joined(separator: " · "); if names.isEmpty { self.connected = false; self.sessions = [] } }
        }
        b.start(queue: queue)
        browser = b
        listTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        listTimer?.invalidate(); listTimer = nil
        browser?.cancel(); browser = nil
        queue.async {
            for c in self.connections.values { c.cancel() }
            self.connections = [:]
            self.known = []
        }
        DispatchQueue.main.async { self.connected = false; self.sessions = [] }
    }

    /// Ask the Mac(s) for the current session list.
    func refresh() { if connected { send("list") } }

    /// Called on `queue`.
    private func connect(to endpoint: NWEndpoint) {
        let c = NWConnection(to: endpoint, using: .udp)
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.connected = true; self.send("ping"); self.send("list") }
            case .failed, .cancelled:
                // forget it; if Bonjour still advertises the Mac, try again in a moment instead of talking to a dead connection
                if let c = c, self.connections[endpoint] === c { self.connections[endpoint] = nil }
                let anyLeft = !self.connections.isEmpty
                DispatchQueue.main.async { if !anyLeft { self.connected = false } }
                if case .failed = state {
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self = self, self.known.contains(endpoint), self.connections[endpoint] == nil else { return }
                        self.connect(to: endpoint)
                    }
                }
            default: break
            }
        }
        connections[endpoint] = c
        c.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let d = data, let s = String(data: d, encoding: .utf8) { DispatchQueue.main.async { self?.handle(s) } }
            if error == nil { self?.receive(c) }
        }
    }

    private func handle(_ raw: String) {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        guard let first = lines.first else { return }
        if first == "list" {
            // With several Macs the lists would interleave; good enough for one Mac, which is the normal case.
            sessions = lines.dropFirst().compactMap { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 4 else { return nil }
                return RemoteSession(id: f[0], name: f[1], state: f[2], kind: f[3])
            }
        } else if first != "pong" {
            lastReply = first.trimmingCharacters(in: .whitespacesAndNewlines)
            // an action changes states; re-list shortly after
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refresh() }
        }
    }

    func send(_ line: String) {
        queue.async {
            for c in self.connections.values {
                c.send(content: (line + "\n").data(using: .utf8), completion: .contentProcessed { _ in })
            }
        }
    }
}
