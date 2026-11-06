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
            VStack(spacing: 28) {
                Spacer()
                Text("Whiplash").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(status).font(.callout).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                Button { crack(strength: 3) } label: {
                    Text("WHIP!")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 220, height: 220)
                        .background(Circle().fill(Color.black.opacity(cracked ? 0.9 : 0.75)))
                        .scaleEffect(cracked ? 0.92 : 1)
                        .animation(.spring(duration: 0.25), value: cracked)
                }
                .buttonStyle(.plain)
                .disabled(!sender.connected)
                .opacity(sender.connected ? 1 : 0.5)
                VStack(spacing: 6) {
                    Text("Flick the phone like a whip").font(.headline).foregroundStyle(.white)
                    Text(flick.lastStrength > 0 ? String(format: "last flick %.1f g", flick.lastStrength) : "snap your wrist — crack!")
                        .font(.footnote).foregroundStyle(.white.opacity(0.8))
                    if phone.watchReachable { Text("Apple Watch connected — snap your wrist there too").font(.footnote).foregroundStyle(.white.opacity(0.8)) }
                }
                Spacer()
                Text("\(count) cracks").font(.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
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

    private func crack(strength: Double) {
        Crack.shared.play(strength: strength)
        sender.send(String(format: "flick %.1f", strength))
        sender.send("whipall")
        count += 1
        cracked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { cracked = false }
    }
}
