import SwiftUI

struct ContentView: View {
    @StateObject private var sender = RemoteSender()
    @StateObject private var flick = Flick()
    @StateObject private var phone = PhoneSession()
    @State private var cracked = false
    @State private var count = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.95, green: 0.58, blue: 0.45), Color(red: 0.69, green: 0.27, blue: 0.15)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Whiplash").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(status).font(.footnote).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)

                // the big one: flick or tap → everyone idle
                Button { crack(strength: 3) } label: {
                    Text("WHIP!")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 150, height: 150)
                        .background(Circle().fill(Color.black.opacity(cracked ? 0.9 : 0.75)))
                        .scaleEffect(cracked ? 0.92 : 1)
                        .animation(.spring(duration: 0.25), value: cracked)
                }
                .buttonStyle(.plain)
                .disabled(!sender.connected)
                .opacity(sender.connected ? 1 : 0.5)

                HStack(spacing: 12) {
                    Button { act("treatall") } label: { Label("Treat all", systemImage: "carrot.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button { sender.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).tint(.white)
                }
                .disabled(!sender.connected)

                // what the Mac said back — this is how you know it landed even with the sound off
                Text(reply)
                    .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))

                // one row per session: name, state, whip, treat
                if sender.sessions.isEmpty {
                    Text(sender.connected ? "No agent sessions on the Mac right now." : " ")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                } else {
                    List(sender.sessions) { s in
                        HStack(spacing: 10) {
                            Text(icon(s.state)).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(stateText(s.state) + " · " + kindText(s.kind)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Button { act("whip " + s.id) } label: { Image(systemName: "bolt.fill").frame(width: 34, height: 30) }
                                .buttonStyle(.borderedProminent).tint(.orange)
                            Button { act("treat " + s.id) } label: { Image(systemName: "carrot.fill").frame(width: 34, height: 30) }
                                .buttonStyle(.borderedProminent).tint(.green)
                        }
                        .buttonStyle(.borderless)
                        .listRowBackground(Color.white.opacity(0.9))
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 2) {
                    Text("Flick the phone like a whip").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    Text(flick.lastStrength > 0 ? String(format: "last flick %.1f g · %d cracks", flick.lastStrength, count) : "snap your wrist — crack!")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                    if phone.watchReachable { Text("Apple Watch connected — snap your wrist there too").font(.caption).foregroundStyle(.white.opacity(0.8)) }
                }
            }
            .padding()
        }
        .onAppear {
            sender.start()
            flick.onFlick = { g in crack(strength: g) }
            flick.start()
            phone.onWatchFlick = { g in crack(strength: g) }
        }
        .onDisappear { sender.stop(); flick.stop() }
    }

    private var status: String {
        if sender.connected { return "Connected to \(sender.macName.isEmpty ? "your Mac" : sender.macName)" + (sender.macName.contains(" · ") ? " — every one of them gets whipped" : "") }
        if !sender.macName.isEmpty { return "Found \(sender.macName), connecting…" }
        return "Looking for a Mac running Whiplash on this Wi‑Fi…\nTurn on Settings ▸ Whip with your body ▸ Accept iPhone / Apple Watch remote."
    }

    /// The Mac's last answer, made readable.
    private var reply: String {
        let r = sender.lastReply
        if r.isEmpty { return sender.connected ? "Ready. Flick, tap, or pick a critter." : "…" }
        if r.hasPrefix("ok whipped ") { return "Whack! " + r.dropFirst("ok whipped ".count) + " whipped" }
        if r.hasPrefix("ok treated ") { return "Yum! " + r.dropFirst("ok treated ".count) + " treated" }
        if r.hasPrefix("ok nobody") { return "Nobody to " + (r.contains("whip") ? "whip" : "treat") + " — everyone's busy / asleep" }
        if r.hasPrefix("ok ") { return String(r.dropFirst(3)) }
        if r.hasPrefix("err ") { return "Mac says: " + r.dropFirst(4) }
        return r
    }

    private func icon(_ state: String) -> String {
        switch state { case "working": return "🔨"; case "waiting": return "💬"; case "strike": return "🥕"; default: return "💤" }
    }
    private func stateText(_ state: String) -> String {
        switch state { case "working": return "working"; case "waiting": return "waiting for you"; case "strike": return "on strike (no quota)"; default: return "resting" }
    }
    private func kindText(_ kind: String) -> String {
        switch kind { case "claudeCode": return "Claude Code"; case "claudeApp": return "Claude app"; case "codex": return "Codex"; case "cursor": return "Cursor"
        case "gemini": return "Gemini"; case "antigravity": return "Antigravity"; default: return "agent" }
    }

    private func act(_ line: String) {
        sender.send(line)
        if line.hasPrefix("whip") { Crack.shared.play(strength: 3); bump() }
    }

    private func crack(strength: Double) {
        Crack.shared.play(strength: strength)
        sender.send(String(format: "flick %.1f", strength))
        sender.send("whipall")
        bump()
    }

    private func bump() {
        count += 1
        cracked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { cracked = false }
    }
}
