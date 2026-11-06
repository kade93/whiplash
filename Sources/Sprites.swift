import SwiftUI
import AppKit

// MARK: - 어떤 에이전트인지

enum AgentKind: String, CaseIterable, Identifiable {
    case claudeCode, claudeApp, codex, cursor, gemini, antigravity, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode:  return "Claude Code"
        case .claudeApp:   return t("Claude 앱")
        case .codex:       return "Codex"
        case .cursor:      return "Cursor"
        case .gemini:      return "Gemini CLI"
        case .antigravity: return "Antigravity"
        case .other:       return t("기타 에이전트")
        }
    }

    var order: Int { AgentKind.allCases.firstIndex(of: self) ?? 0 }

    /// 막대 그래프에 쓰는 색 (캐릭터 몸 색과 맞춤)
    var barColor: Color {
        switch self {
        case .claudeCode:  return Color(hex: 0xE07A5F)
        case .claudeApp:   return Color(hex: 0xD9A27A)
        case .codex:       return Color(hex: 0x7FBFD3)
        case .cursor:      return Color(hex: 0x9AA1B0)
        case .gemini:      return Color(hex: 0x5A7FD6)
        case .antigravity: return Color(hex: 0x6FA8DC)
        case .other:       return Color(hex: 0x7DB676)
        }
    }

    var sprite: Sprite {
        switch self {
        case .claudeCode:  return Sprite.crab
        case .claudeApp:   return Sprite.sandCrab
        case .codex:       return Sprite.jelly
        case .cursor:      return Sprite.squid
        case .gemini:      return Sprite.puffer
        case .antigravity: return Sprite.whale
        case .other:       return Sprite.blob
        }
    }
}

/// 픽셀 그림을 NSImage 로 (메뉴 막대 아이콘, 커서)
func pixelImage(rows: [String], cell: CGFloat, color: @escaping (Character) -> Color?) -> NSImage {
    let cols = rows.first?.count ?? 0
    let size = NSSize(width: CGFloat(cols) * cell, height: CGFloat(rows.count) * cell)
    return NSImage(size: size, flipped: true) { _ in
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = color(ch) else { continue }
                NSColor(c).setFill()
                NSBezierPath(rect: NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)).fill()
            }
        }
        return true
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - 픽셀 캐릭터 (12×10 도트)
// K 먹 테두리 · E 눈 · B 몸 · L 밝은 부분 · A 포인트 · C 볼터치 · . 빈칸

struct Sprite {
    let friend: String
    let rows: [String]
    let body: Color
    let light: Color
    let accent: Color
    let cheek: Color

    static let ink = Color(hex: 0x2A2433)
    static let water = Color(hex: 0xE9F3F4)

    func color(for ch: Character) -> Color? {
        switch ch {
        case "K", "E": return Sprite.ink
        case "B": return body
        case "L": return light
        case "A": return accent
        case "C": return cheek
        default:  return nil
        }
    }

    private static let crabRows = [
        "KK........KK",
        "KAK......KAK",
        "KAAK....KAAK",
        ".KAK....KAK.",
        "..KKKKKKKK..",
        ".KBLBBBBBBK.",
        "KBBEBBBBEBBK",
        "KBCBBKKBBCBK",
        ".KKKKKKKKKK.",
        ".K.K....K.K.",
    ]

    static let crab = Sprite(friend: "꽃게", rows: crabRows,
        body: Color(hex: 0xE07A5F), light: Color(hex: 0xF6B9A3),
        accent: Color(hex: 0xC4553B), cheek: Color(hex: 0xFFD3C4))

    static let sandCrab = Sprite(friend: "모래게", rows: crabRows,
        body: Color(hex: 0xD9A27A), light: Color(hex: 0xF1D3B8),
        accent: Color(hex: 0xB07A52), cheek: Color(hex: 0xF2A7B8))

    static let jelly = Sprite(friend: "해파리", rows: [
        "...KKKKKK...",
        "..KLLBBBBK..",
        ".KLBBBBBBBK.",
        ".KBBEBBEBBK.",
        ".KBCBKKBCBK.",
        ".KKKKKKKKKK.",
        "..A.A..A.A..",
        "..A..A.A..A.",
        "...A.A..A.A.",
        "..A.A..A.A..",
    ], body: Color(hex: 0xBFE8EA), light: Color(hex: 0xFFFFFF),
       accent: Color(hex: 0x7FBFD3), cheek: Color(hex: 0xF2A7B8))

    static let puffer = Sprite(friend: "복어", rows: [
        "...K.KK.K...",
        "....KKKK....",
        "..KKLLBBKK..",
        ".KLLBBBBBBK.",
        "AKBBEBBEBBKA",
        "AKBCBBBBCBKA",
        ".KLLLKKLLLK.",
        "..KLLLLLLK..",
        "...KKKKKK...",
        "..K..KK..K..",
    ], body: Color(hex: 0x8FB3F0), light: Color(hex: 0xDCE8FF),
       accent: Color(hex: 0x5A7FD6), cheek: Color(hex: 0xF2A7B8))

    static let squid = Sprite(friend: "오징어", rows: [
        ".....KK.....",
        "....KBBK....",
        "...KBLBBK...",
        "..KBLBBBBK..",
        "KAKBBBBBBKAK",
        ".KBBEBBEBBK.",
        ".KBCBBBBCBK.",
        "..KKKKKKKK..",
        "..K.K..K.K..",
        ".K..K..K..K.",
    ], body: Color(hex: 0x8C93A3), light: Color(hex: 0xC4C9D4),
       accent: Color(hex: 0x5D6372), cheek: Color(hex: 0xF2A7B8))

    static let whale = Sprite(friend: "고래", rows: [
        "..A.A.......",
        "...A........",
        "..KKKKKK..KK",
        ".KLLBBBBKKAK",
        "KLBBBBBBBBK.",
        "KBBEBBBBBBK.",
        "KBCBBBBBBBK.",
        "KAAAAAAAAK..",
        ".KKKKKKKK...",
        "............",
    ], body: Color(hex: 0x6FA8DC), light: Color(hex: 0xB8D8F2),
       accent: Color(hex: 0xE8F2FB), cheek: Color(hex: 0xF2A7B8))

    static let blob = Sprite(friend: "물방울", rows: [
        ".....KK.....",
        "....KLLK....",
        "...KLBBBK...",
        "..KLBBBBBK..",
        ".KBBEBBEBBK.",
        ".KBCBBBBCBK.",
        ".KBBBKKBBBK.",
        "..KBBBBBBK..",
        "...KKKKKK...",
        "............",
    ], body: Color(hex: 0xA8D5A2), light: Color(hex: 0xE0F2DC),
       accent: Color(hex: 0x7DB676), cheek: Color(hex: 0xF2A7B8))
}

// MARK: - 그리기

/// 일할 때: 위아래로 한 칸씩 통통 / 쉴 때: 눈 감고 z / 코어 하나 이상 쓰면: 땀방울
struct SpriteCanvas: View {
    let sprite: Sprite
    let awake: Bool
    let bob: Bool
    let sweat: Bool
    let cell: CGFloat
    var hot = false         // 과부하: 머리에서 김

    var body: some View {
        Canvas { ctx, size in
            let cols = CGFloat(sprite.rows.first?.count ?? 0)
            let rowCount = CGFloat(sprite.rows.count)
            let ox = ((size.width - cols * cell) / 2).rounded()
            let oy = ((size.height - rowCount * cell) / 2).rounded() + (bob ? -cell : 0)

            for (y, row) in sprite.rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = sprite.color(for: ch) else { continue }
                    var r = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell,
                                   width: cell, height: cell)
                    if ch == "E" && !awake {          // 감은 눈
                        r.origin.y += cell * 0.6
                        r.size.height = cell * 0.4
                    }
                    ctx.fill(Path(r), with: .color(color))
                }
            }

            let unit = max(1, (cell / 3).rounded())
            let rightX = ox + cols * cell
            if !awake {                                // z
                let z = ["111", "010", "111"]
                for (y, row) in z.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "1" {
                        let r = CGRect(x: rightX + CGFloat(x) * unit, y: 1 + CGFloat(y) * unit,
                                       width: unit, height: unit)
                        ctx.fill(Path(r), with: .color(Sprite.ink.opacity(0.55)))
                    }
                }
            } else if sweat {                          // 땀방울
                let r = CGRect(x: rightX, y: oy + cell, width: unit * 2, height: unit * 3)
                ctx.fill(Path(r), with: .color(Color(hex: 0x6CB8F0)))
                if hot {
                    let r2 = CGRect(x: ox - unit * 2, y: oy + cell * 2, width: unit * 2, height: unit * 3)
                    ctx.fill(Path(r2), with: .color(Color(hex: 0x6CB8F0)))
                }
            }
            if hot {                                   // 김 (박자마다 자리 바꿈)
                let puffs: [(CGFloat, CGFloat, CGFloat)] = bob
                    ? [(3, 0, 2), (6, -2, 1.5), (1, -3, 1)]
                    : [(2, -1, 2), (5, 0, 1.5), (7, -3, 1)]
                for (px, py, sz) in puffs {
                    let r = CGRect(x: ox + px * cell, y: py * cell, width: sz * unit, height: sz * unit)
                    ctx.fill(Path(r), with: .color(Color.primary.opacity(0.35)))
                }
            }
        }
    }
}

// MARK: - 설치된 앱 아이콘

/// 맥에 설치된 앱의 아이콘을 실행 중에 불러온다. 없으면 nil → 픽셀 캐릭터로.
enum AppIcons {
    private static var cache: [AgentKind: NSImage?] = [:]

    static func icon(for kind: AgentKind) -> NSImage? {
        if let hit = cache[kind] { return hit }
        let names: [String]
        switch kind {
        case .claudeCode, .claudeApp: names = ["Claude.app"]
        case .codex:                  names = ["Codex.app", "ChatGPT.app"]
        case .cursor:                 names = ["Cursor.app"]
        case .antigravity:            names = ["Antigravity.app"]
        case .gemini, .other:         names = []
        }
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        var found: NSImage? = nil
        search: for name in names {
            for dir in dirs {
                let path = dir + "/" + name
                if FileManager.default.fileExists(atPath: path) {
                    found = NSWorkspace.shared.icon(forFile: path)
                    break search
                }
            }
        }
        cache[kind] = .some(found)
        return found
    }
}

/// 아이콘 모드에서 쓰는 z·땀방울 표시
struct MarkCanvas: View {
    let awake: Bool
    let sweat: Bool
    let unit: CGFloat

    var body: some View {
        Canvas { ctx, size in
            if !awake {
                let z = ["111", "010", "111"]
                for (y, row) in z.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "1" {
                        let r = CGRect(x: size.width - 3 * unit + CGFloat(x) * unit,
                                       y: CGFloat(y) * unit, width: unit, height: unit)
                        ctx.fill(Path(r), with: .color(Color.primary.opacity(0.7)))
                    }
                }
            } else if sweat {
                let r = CGRect(x: size.width - 2 * unit, y: 0, width: unit * 2, height: unit * 3)
                ctx.fill(Path(r), with: .color(Color(hex: 0x6CB8F0)))
            }
        }
        .frame(width: unit * 4, height: unit * 4)
    }
}

// MARK: - 연장과 쇠사슬 (일하는 캐릭터만)
// K 먹 · W 나무 · M 쇠 · P 종이 · Y 연필 노랑 · R 지우개 · B 바다 · G 땅 · . 빈칸

enum ToolArt {
    static func rows(_ c: Chore) -> [String] {
        switch c {
        case .read: return [
            ".KKKKK.",
            "KPPKPPK",
            "KPPKPPK",
            "KPPKPPK",
            "KPPKPPK",
            ".KKKKK.",
        ]
        case .write: return [
            ".....KK",
            "....KRK",
            "...KYK.",
            "..KYK..",
            ".KYK...",
            "KKK....",
        ]
        case .run: return [
            "KKKKK..",
            "KMMMMK.",
            "KKKKK..",
            "..KWK..",
            "..KWK..",
            "..KWK..",
            "..KKK..",
        ]
        case .search: return [
            ".KKK...",
            "KPPPK..",
            "KPPPK..",
            "KPPPK..",
            ".KKKKK.",
            "....KWK",
            ".....KK",
        ]
        case .web: return [
            ".KKKKK.",
            "KBBGBBK",
            "KGBBBGK",
            "KBBGBBK",
            "KBGBBBK",
            "KBBBGBK",
            ".KKKKK.",
        ]
        case .think: return [
            ".KKKKK.",
            "KPPPPPK",
            "KPKPKPK",
            "KPPPPPK",
            ".KKKKK.",
            "...KK..",
            "....K..",
        ]
        case .answer: return [
            ".KKKKK.",
            "KPPPPPK",
            "KPKKKPK",
            "KPPPPPK",
            ".KKKKK.",
            "..KK...",
            "..K....",
        ]
        case .strike: return [          // 피켓: 「파업」 팻말
            "KKKKKKKKK",
            "KPPPPPPPK",
            "KPKKPKKPK",
            "KPPPPPPPK",
            "KKKKKKKKK",
            "....W....",
            "....W....",
            "....W....",
        ]
        case .delegate, .none: return []
        }
    }

    static let carrot = [            // 당근 (5×8)
        "..G..",
        ".GGG.",
        "G.G.G",
        ".OOO.",
        ".OOO.",
        ".OOO.",
        "..O..",
        "..O..",
    ]
    static let carrotEaten = [       // 뽑힌 자리: 흙만
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
        "..D..",
        ".DDD.",
    ]

    static func color(_ ch: Character) -> Color? {
        switch ch {
        case "K": return Sprite.ink
        case "W": return Color(hex: 0x8B5A2B)
        case "M": return Color(hex: 0xB8BEC8)
        case "P": return Color(hex: 0xFFFBEF)
        case "Y": return Color(hex: 0xF2C14E)
        case "R": return Color(hex: 0xE98A8A)
        case "B": return Color(hex: 0x5FA8E0)
        case "G": return Color(hex: 0x7DB676)
        case "O": return Color(hex: 0xF28C28)
        case "D": return Color(hex: 0x8B6B4A)
        default:  return nil
        }
    }

    static let chain = [        // 발목 사슬 + 쇠공
        "K.K....",
        ".K.K...",
        "...KKK.",
        "..KMMMK",
        "..KMMMK",
        "...KKK.",
    ]
}

struct PixelArt: View {
    let rows: [String]
    let cell: CGFloat
    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = ToolArt.color(ch) else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                             with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(rows.first?.count ?? 0) * cell, height: CGFloat(rows.count) * cell)
    }
}

/// 손에 든 연장. 박자(bob)에 맞춰 휘두른다. 부하를 시키는 중이면 채찍.
struct ToolInHand: View {
    let chore: Chore
    let bob: Bool
    let cell: CGFloat

    var body: some View {
        let unit = max(1, (cell * 0.8).rounded())
        Group {
            if chore == .delegate {
                WhipCanvas(cell: unit)
            } else if chore != .none {
                PixelArt(rows: ToolArt.rows(chore), cell: unit)
            }
        }
        .rotationEffect(.degrees(chore == .strike ? (bob ? -8 : 8) : (bob ? -28 : 6)), anchor: .bottomLeading)
        .animation(.easeOut(duration: 0.18), value: bob)
    }
}

/// 에이전트 한 칸: 물빛 칸 안의 픽셀 캐릭터 (설정하면 앱 아이콘)
/// 일하는 중이면 연장을 들고 발목에 쇠공을 찬다.
struct SpriteTile: View {
    let kind: AgentKind
    var awake: Bool
    var bob: Bool = false
    var sweat: Bool = false
    var cell: CGFloat = 3
    var chore: Chore = .none
    var boxed = true            // 뒤에 물빛 칸
    var hot = false             // 과부하
    var angry = false           // 화남: 빨개지고 💢

    @AppStorage("useAppIcons") private var useAppIcons = false   // 기본은 캐릭터

    var body: some View {
        base
            .overlay(RoundedRectangle(cornerRadius: cell * 3).fill(Color.red.opacity(angry ? 0.28 : 0)).allowsHitTesting(false))
            .overlay(alignment: .topTrailing) {
                if angry {
                    Text("💢").font(.system(size: cell * 4)).offset(x: cell * 2, y: -cell * 2.5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if awake || chore == .strike { ToolInHand(chore: chore, bob: bob, cell: cell).offset(x: cell * 1.5, y: cell * 0.5) }
            }
            .overlay(alignment: .bottomLeading) {
                if awake && chore != .strike {
                    PixelArt(rows: ToolArt.chain, cell: max(1, (cell * 0.6).rounded()))
                        .offset(x: -cell * 1.2, y: cell * 0.8)
                }
            }
    }

    @ViewBuilder
    private var base: some View {
        if useAppIcons, let icon = AppIcons.icon(for: kind) {
            let side = cell * 13 + 1
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .opacity(awake ? 1 : 0.45)
                .offset(y: bob ? -2 : 0)
                .overlay(RoundedRectangle(cornerRadius: cell * 3).fill(Color.red.opacity(hot ? 0.25 : 0)))
                .overlay(alignment: .topTrailing) {
                    MarkCanvas(awake: awake, sweat: sweat, unit: max(1, (cell / 3).rounded()))
                        .offset(x: cell, y: -cell)
                }
                .frame(width: cell * 14 + 2, height: side)
        } else {
            SpriteCanvas(sprite: kind.sprite, awake: awake, bob: bob, sweat: sweat, cell: cell, hot: hot)
                .frame(width: cell * 14 + 2, height: cell * 13 + 1)
                .background(
                    RoundedRectangle(cornerRadius: cell * 3, style: .continuous)
                        .fill(boxed ? (hot ? Color(hex: 0xFFD9D2) : Sprite.water) : Color.clear)
                )
        }
    }
}
