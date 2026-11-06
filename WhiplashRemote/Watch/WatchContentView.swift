import SwiftUI
import WatchKit

struct WatchContentView: View {
    @StateObject private var session = WatchSession()
    @StateObject private var flick = Flick()
    @State private var cracked = false
    @State private var count = 0

    var body: some View {
        VStack(spacing: 10) {
            Text("Whiplash").font(.headline)
            Button { crack(strength: 3) } label: {
                Text("WHIP!").font(.system(size: 22, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .scaleEffect(cracked ? 0.92 : 1)
            .animation(.spring(duration: 0.25), value: cracked)
            Text(session.phoneReachable ? "Snap your wrist — crack!" : "Open Whiplash Remote on your iPhone")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("\(count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            flick.onFlick = { g in crack(strength: g) }
            flick.start()
        }
        .onDisappear { flick.stop() }
    }

    private func crack(strength: Double) {
        WKInterfaceDevice.current().play(.click)
        session.sendFlick(strength)
        count += 1
        cracked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { cracked = false }
    }
}
