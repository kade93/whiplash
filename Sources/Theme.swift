import AppKit
import SwiftUI

// MARK: - 테마
// 상태 글자색(일하는 중·내 차례·과부하), 창 배경, 캐릭터 이름표 색이 테마를 따라간다.
// 캐릭터 몸 색과 종류별 막대 색은 테마와 상관없이 그대로.

struct Theme: Identifiable, Equatable {
    let id: String
    let title: String
    let dark: Bool                          // 창의 appearance (글자 primary/secondary 가 따라감)
    let material: NSVisualEffectView.Material
    let solid: NSColor?                     // 있으면 유리 대신 이 색으로 (살짝 투명)
    let working: Color                      // 「실행 중 · …」
    let waiting: Color                      // 「답 기다리는 중」, 배지
    let hot: Color                          // 과부하·화남·파업
    let pill: Color                         // 돌아다닐 때 이름표 배경
    let pillText: Color
    let water: Color                        // 캐릭터 뒤 물빛 칸

    static let all: [Theme] = [
        Theme(id: "glass", title: "Glass (default)", dark: true, material: .hudWindow, solid: nil,
              working: Color(hex: 0xFFB08A), waiting: Color(hex: 0xFFC84A), hot: Color(hex: 0xFF6B5B),
              pill: Color.black.opacity(0.6), pillText: .white, water: Color(hex: 0xE9F3F4)),
        Theme(id: "paper", title: "Light paper", dark: false, material: .popover, solid: nil,
              working: Color(hex: 0xB8471F), waiting: Color(hex: 0x9A6B00), hot: Color(hex: 0xC0392B),
              pill: Color.white.opacity(0.85), pillText: Color(hex: 0x2A2433), water: Color(hex: 0xD9ECF0)),
        Theme(id: "night", title: "Deep night", dark: true, material: .hudWindow, solid: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 0.94),
              working: Color(hex: 0x7EE787), waiting: Color(hex: 0xFFD166), hot: Color(hex: 0xFF6B6B),
              pill: Color(hex: 0x0B0E16).opacity(0.85), pillText: .white, water: Color(hex: 0x1E2535)),
        Theme(id: "carrot", title: "Carrots", dark: true, material: .hudWindow, solid: NSColor(srgbRed: 0.24, green: 0.16, blue: 0.11, alpha: 0.95),
              working: Color(hex: 0xFFB347), waiting: Color(hex: 0xFFE08A), hot: Color(hex: 0xFF6F61),
              pill: Color(hex: 0x3A2A1E).opacity(0.9), pillText: Color(hex: 0xFFF1DC), water: Color(hex: 0xEADFC8)),
        Theme(id: "terminal", title: "Terminal", dark: true, material: .hudWindow, solid: NSColor(srgbRed: 0.03, green: 0.05, blue: 0.03, alpha: 0.96),
              working: Color(hex: 0x33FF66), waiting: Color(hex: 0xFFFF66), hot: Color(hex: 0xFF3355),
              pill: Color.black.opacity(0.9), pillText: Color(hex: 0x33FF66), water: Color(hex: 0x0F1A10)),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }

    /// 뷰들이 읽는 현재 테마 (Model 이 바꾸고 objectWillChange 로 다시 그린다)
    static var current: Theme = named(UserDefaults.standard.string(forKey: "theme") ?? "glass")
}

var waitColor: Color { Theme.current.waiting }
var hotColor: Color { Theme.current.hot }
var workingColor: Color { Theme.current.working }
