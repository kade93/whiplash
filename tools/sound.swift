// 채찍 소리 합성.  swiftc -O tools/sound.swift -o /tmp/sound && /tmp/sound Resources
// 「후-췻!」 = 휘두르는 바람(점점 커지는 노이즈) → 스냅(주파수 급강하) + 크랙 + 둔탁음 + 꼬리 → 「아야」.
// 연타 변형: whip1(기본) · whip2(높고 빠름, 「아얏」) · whip3(더블 크랙, 긴 「으아악」)
import Foundation

let sr = 44100.0
var seed: UInt64 = 0x9E3779B97F4A7C15
func noise() -> Double {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return Double(seed % 20001) / 10000.0 - 1
}
func env(_ t: Double, start: Double, tau: Double) -> Double { t < start ? 0 : exp(-(t - start) / tau) }

/// 음절 하나: 성대 파형(기음 f0 → f0End)에 모음 포먼트(F1,F2,F3)를 씌운다. 시작 포먼트에서 끝 포먼트로 미끄러진다.
struct Syllable {
    let start: Double, dur: Double
    let f0: Double, f0End: Double
    let fStart: (Double, Double, Double), fEnd: (Double, Double, Double)
    let amp: Double
    var attack: Double = 0.02
    var stop = false        // 끝을 막소리처럼 뚝 끊기 (악!)
}

/// 2차 공명 필터 (포먼트)
struct Resonator {
    var y1 = 0.0, y2 = 0.0
    mutating func run(_ x: Double, f: Double, bw: Double) -> Double {
        let r = exp(-.pi * bw / sr)
        let a1 = 2 * r * cos(2 * .pi * f / sr), a2 = -r * r
        let y = (1 - r) * x + a1 * y1 + a2 * y2
        y2 = y1; y1 = y
        return y
    }
}

let A: (Double, Double, Double)  = (760, 1250, 2700)    // 아
let I: (Double, Double, Double)  = (320, 2300, 3000)    // 이 (야의 머리)
let EU: (Double, Double, Double) = (380, 1500, 2500)    // 으

struct Variant {
    let whoosh: Double     // 바람 길이
    let pitch: Double      // 크랙 음높이 배율
    let cracks: [Double]   // 크랙 시작 시각들 (바람 끝 기준)
    let syllables: [Syllable]
    let length: Double
}

func render(_ v: Variant) -> [Double] {
    let n = Int(sr * v.length)
    var out = [Double](repeating: 0, count: n)
    var lp = 0.0, prevNoise = 0.0, tail = 0.0
    seed = 0x9E3779B97F4A7C15
    for i in 0..<n {
        let t = Double(i) / sr
        let raw = noise()
        var s = 0.0
        // 바람: 저역 노이즈, 컷오프와 음량이 함께 올라간다 (후-)
        if t < v.whoosh {
            let u = t / v.whoosh
            let a = 0.05 + 0.95 * u
            lp += a * (raw - lp)
            s += lp * pow(u, 1.8) * 0.65
        }
        for c in v.cracks {
            let tc = t - (v.whoosh + c)
            guard tc >= 0 else { continue }
            // 스냅: 2800→250Hz 로 10ms 안에 떨어지는 사인 (췻)
            let sweep = min(tc, 0.010) / 0.010
            let f = 2800 * v.pitch * pow(250 / 2800, sweep)
            s += sin(2 * .pi * f * tc) * env(tc, start: 0, tau: 0.006) * 1.0
            // 크랙: 하이패스 노이즈 — 진짜 채찍처럼 아주 짧고 세게, 2ms 뒤에 한 번 더 (이중 파열)
            let hp = raw - prevNoise * 0.93
            s += hp * env(tc, start: 0.0005, tau: 0.007) * 1.7
            s += hp * env(tc, start: 0.0025, tau: 0.005) * 1.1
            // 둔탁음 (몸통)
            s += sin(2 * .pi * 70 * v.pitch * tc) * env(tc, start: 0.002, tau: 0.035) * 0.45
            // 꼬리: 방 울림 — 저역으로 갈수록 길게
            tail += 0.12 * (raw - tail)
            s += tail * env(tc, start: 0.010, tau: 0.16) * 0.28
            s += raw * env(tc, start: 0.012, tau: 0.05) * 0.10
        }
        prevNoise = raw
        s += voice.sample(t: t, offset: v.whoosh, syllables: v.syllables) * 0.8
        out[i] = tanh(s * 1.25) * 0.95
    }
    return out
}

/// 목소리: 음절마다 성대 펄스열 → 포먼트 3개. 상태(위상·필터)는 렌더 동안 유지
final class Voice {
    var phase = 0.0
    var f = [Resonator(), Resonator(), Resonator()]
    func sample(t: Double, offset: Double, syllables: [Syllable]) -> Double {
        var out = 0.0
        for syl in syllables {
            let st = offset + syl.start
            guard t >= st, t < st + syl.dur else { continue }
            let u = (t - st) / syl.dur
            // 기음: 시작에서 끝으로 미끄러지고 빠르게 떨린다 (작은 생물, 사람 아님)
            let f0 = syl.f0 * pow(syl.f0End / syl.f0, u) * (1 + 0.035 * sin(2 * .pi * 9 * t))
            phase += f0 / sr
            if phase >= 1 { phase -= 1 }
            // 파형: 배음 적은 동글동글한 만화 음색 (사인 + 약한 홀수 배음)
            var src = sin(2 * .pi * phase)
            src += 0.35 * sin(2 * .pi * 3 * phase) + 0.12 * sin(2 * .pi * 5 * phase)
            src *= 0.7
            // 포먼트: 시작 모음 → 끝 모음
            let g = min(1, u / 0.55)                       // 전반부에 미끄러짐
            let k = 1.35                                   // 작은 몸 = 공명이 높다
            let F1 = (syl.fStart.0 + (syl.fEnd.0 - syl.fStart.0) * g) * k
            let F2 = (syl.fStart.1 + (syl.fEnd.1 - syl.fStart.1) * g) * k
            let F3 = (syl.fStart.2 + (syl.fEnd.2 - syl.fStart.2) * g) * k
            var y = f[0].run(src, f: F1, bw: 120) * 1.0
            y += f[1].run(src, f: F2, bw: 160) * 0.45
            y += f[2].run(src, f: F3, bw: 200) * 0.15
            y += src * 0.25                                // 원음도 조금 섞어 또렷하게
            // 음량: 빠른 어택, 끝은 부드럽게 (stop 이면 뚝)
            var a = min(1, (t - st) / syl.attack)
            let tail = syl.stop ? 0.04 : 0.35
            if u > 1 - tail { a *= (1 - u) / tail }
            out += y * a * syl.amp
        }
        return out
    }
}
let voice = Voice()

func writeWAV(_ samples: [Double], _ path: String) {
    var data = Data()
    func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let n = samples.count
    data.append("RIFF".data(using: .ascii)!); le32(UInt32(36 + n * 2)); data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!); le32(16); le16(1); le16(1); le32(UInt32(sr)); le32(UInt32(sr) * 2); le16(2); le16(16)
    data.append("data".data(using: .ascii)!); le32(UInt32(n * 2))
    for v in samples { le16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32767))) }
    try! data.write(to: URL(fileURLWithPath: path))
}

let dir = CommandLine.arguments[1]
let variants: [(String, Variant)] = [
    // 목소리는 사람이 아니라 작은 생물: 음높이 500~860Hz, 공명 1.35배, 배음 적게, 떨림 빠르게
    // 1타: 「아-야」 놀란 목소리. 아(높게 시작해 내려감) → 야(이→아 미끄러짐, 더 내려감)
    ("whip1", Variant(whoosh: 0.09, pitch: 1.0, cracks: [0], syllables: [
        Syllable(start: 0.12, dur: 0.15, f0: 640, f0End: 500, fStart: A, fEnd: A, amp: 0.9),
        Syllable(start: 0.28, dur: 0.24, f0: 600, f0End: 380, fStart: I, fEnd: A, amp: 0.85),
    ], length: 0.70)),
    // 2타: 「아얏!」 더 높고 짧게, 끝을 뚝
    ("whip2", Variant(whoosh: 0.06, pitch: 1.25, cracks: [0], syllables: [
        Syllable(start: 0.10, dur: 0.11, f0: 760, f0End: 640, fStart: A, fEnd: A, amp: 0.95, attack: 0.01),
        Syllable(start: 0.22, dur: 0.15, f0: 720, f0End: 480, fStart: I, fEnd: A, amp: 0.9, attack: 0.01, stop: true),
    ], length: 0.55)),
    // 3타: 더블 크랙 + 「으아아악!」 길게 올라갔다 뚝
    ("whip3", Variant(whoosh: 0.11, pitch: 1.1, cracks: [0, 0.075], syllables: [
        Syllable(start: 0.18, dur: 0.13, f0: 520, f0End: 680, fStart: EU, fEnd: EU, amp: 0.8),
        Syllable(start: 0.31, dur: 0.40, f0: 680, f0End: 860, fStart: A, fEnd: A, amp: 1.0, attack: 0.03),
        Syllable(start: 0.71, dur: 0.13, f0: 840, f0End: 560, fStart: A, fEnd: A, amp: 0.95, attack: 0.005, stop: true),
    ], length: 1.05)),
]
// 화남: 크랙 뒤 「부! 부!」 — 낮고 거친 버즈 두 번 (귀엽게 화난 생물)
func renderAngry() -> [Double] {
    let length = 0.75
    let n = Int(sr * length)
    var out = [Double](repeating: 0, count: n)
    var phase = 0.0, prevNoise = 0.0
    seed = 0x9E3779B97F4A7C15
    for i in 0..<n {
        let t = Double(i) / sr
        let raw = noise()
        var s = 0.0
        // 짧은 크랙 (맞긴 맞았다)
        if t < 0.08 {
            let sweep = min(t, 0.010) / 0.010
            s += sin(2 * .pi * 2400 * pow(250 / 2400, sweep) * t) * env(t, start: 0, tau: 0.006) * 0.8
            let hp = raw - prevNoise * 0.93
            s += hp * env(t, start: 0.0005, tau: 0.008) * 0.7
        }
        prevNoise = raw
        // 버즈 두 번: 0.14~0.30, 0.38~0.60. 기음 330→260Hz, 사각파에 12Hz 트레몰로, 끝을 뚝
        for (st, dur) in [(0.14, 0.17), (0.38, 0.24)] {
            guard t >= st, t < st + dur else { continue }
            let u = (t - st) / dur
            let f0 = 330 * pow(260 / 330, u) * (1 + 0.05 * sin(2 * .pi * 11 * t))
            phase += f0 / sr; if phase >= 1 { phase -= 1 }
            var sq = 0.0
            var k = 1.0
            while f0 * k < 3200 { sq += sin(2 * .pi * k * phase) / k; k += 2 }   // 홀수 배음 = 사각파
            let trem = 0.65 + 0.35 * sin(2 * .pi * 12 * t)
            var a = min(1, (t - st) / 0.01) * trem
            if u > 0.9 { a *= (1 - u) / 0.1 }
            s += sq * 0.55 * a
        }
        out[i] = tanh(s * 1.3) * 0.9
    }
    return out
}
writeWAV(renderAngry(), "\(dir)/angry.wav")
print("angry.wav")

for (name, v) in variants {
    voice.phase = 0; voice.f = [Resonator(), Resonator(), Resonator()]
    writeWAV(render(v), "\(dir)/\(name).wav")
    print("\(name).wav")
}
