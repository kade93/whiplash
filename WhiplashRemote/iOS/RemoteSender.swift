import Foundation
import Network

/// Finds every Mac running Whiplash on this network (they advertise _whiplash._udp) and sends one-line UDP commands
/// to all of them at once: "whipall", "whip", "flick <g>", "ping".
final class RemoteSender: ObservableObject {
    @Published var macName = ""             // names joined with " · "
    @Published var connected = false
    @Published var lastReply = ""

    private var browser: NWBrowser?
    private var connections: [NWEndpoint: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.kade.whiplash.remote.sender")

    func start() {
        let b = NWBrowser(for: .bonjour(type: "_whiplash._udp", domain: nil), using: .udp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            let endpoints = Set(results.map { $0.endpoint })
            for (ep, c) in self.connections where !endpoints.contains(ep) { c.cancel(); self.connections[ep] = nil }
            for ep in endpoints where self.connections[ep] == nil { self.connect(to: ep) }
            let names = results.compactMap { r -> String? in if case .service(let n, _, _, _) = r.endpoint { return n } else { return nil } }.sorted()
            DispatchQueue.main.async { self.macName = names.joined(separator: " · "); if names.isEmpty { self.connected = false } }
        }
        b.start(queue: queue)
        browser = b
    }

    func stop() {
        browser?.cancel(); browser = nil
        for c in connections.values { c.cancel() }
        connections = [:]
        DispatchQueue.main.async { self.connected = false }
    }

    private func connect(to endpoint: NWEndpoint) {
        let c = NWConnection(to: endpoint, using: .udp)
        c.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready: self?.connected = true; self?.send("ping")
                case .failed, .cancelled: self?.connected = !(self?.connections.isEmpty ?? true)
                default: break
                }
            }
        }
        c.start(queue: queue)
        connections[endpoint] = c
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let d = data, let s = String(data: d, encoding: .utf8) { DispatchQueue.main.async { self?.lastReply = s.trimmingCharacters(in: .whitespacesAndNewlines) } }
            if error == nil { self?.receive(c) }
        }
    }

    func send(_ line: String) {
        for c in connections.values {
            c.send(content: (line + "\n").data(using: .utf8), completion: .contentProcessed { _ in })
        }
    }
}
