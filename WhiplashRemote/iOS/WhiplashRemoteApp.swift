import SwiftUI
import AVFoundation

@main
struct WhiplashRemoteApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Plays the crack on the phone the moment you flick, so it feels like the Mac answered instantly.
final class Crack {
    static let shared = Crack()
    private var players: [AVAudioPlayer] = []
    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for i in 1...3 {
            if let url = Bundle.main.url(forResource: "whip\(i)", withExtension: "wav"), let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay(); players.append(p)
            }
        }
    }
    func play(strength: Double) {
        guard !players.isEmpty else { return }
        let i = strength > 5 ? 2 : (strength > 3.5 ? 1 : 0)
        let p = players[min(i, players.count - 1)]
        p.currentTime = 0; p.volume = 1; p.play()
    }
}
