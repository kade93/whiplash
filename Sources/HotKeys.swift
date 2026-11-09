import AppKit
import Carbon.HIToolbox

// MARK: - 전역 단축키
// 어느 앱을 쓰고 있어도 먹는다. 설정은 ~/Library/Application Support/Whiplash/hotkeys.json
// 예: {"hide": "ctrl+alt+h", "roam": "ctrl+alt+a", ...}  비워 두면("") 그 단축키는 끈다.

enum HotAction: String, CaseIterable {
    case hide, roam, small, cage, whip, whipAll, treatAll, megaphone, gather, panel

    var title: String {
        switch self {
        case .hide:   return t("Hide / show all")
        case .roam:   return t("Roam / window")
        case .small:  return t("Small / large")
        case .cage:   return t("Plant / pull out")
        case .whip:   return t("Whip any idle one")
        case .whipAll: return t("Whip everyone idle")
        case .treatAll: return t("Treat everyone working 🥕")
        case .megaphone: return t("Megaphone — same message to everyone")
        case .gather: return t("Come here (gather at cursor)")
        case .panel:  return t("Show list while roaming (both at once)")
        }
    }

    var defaultCombo: String {
        switch self {
        case .hide:   return "ctrl+alt+h"
        case .roam:   return "ctrl+alt+a"
        case .small:  return "ctrl+alt+m"
        case .cage:   return "ctrl+alt+c"
        case .whip:   return "ctrl+alt+w"
        case .whipAll: return "ctrl+alt+shift+w"
        case .treatAll: return "ctrl+alt+t"
        case .megaphone: return "ctrl+alt+b"
        case .gather: return "ctrl+alt+g"
        case .panel:  return "ctrl+alt+p"
        }
    }
}

struct KeyCombo: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let cocoaModifiers: NSEvent.ModifierFlags
    let keyEquivalent: String      // 메뉴에 표시용

    /// "ctrl+alt+h" 같은 글을 읽는다. 못 읽으면 nil
    static func parse(_ text: String) -> KeyCombo? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }
        var carbon: UInt32 = 0
        var cocoa: NSEvent.ModifierFlags = []
        for mod in parts.dropLast() {
            switch mod {
            case "ctrl", "control", "^":       carbon |= UInt32(controlKey); cocoa.insert(.control)
            case "alt", "option", "opt", "⌥":  carbon |= UInt32(optionKey);  cocoa.insert(.option)
            case "cmd", "command", "⌘":        carbon |= UInt32(cmdKey);     cocoa.insert(.command)
            case "shift", "⇧":                 carbon |= UInt32(shiftKey);   cocoa.insert(.shift)
            default: return nil
            }
        }
        guard carbon != 0, let (code, equiv) = keyCodes[keyName] else { return nil }
        return KeyCombo(keyCode: code, carbonModifiers: carbon, cocoaModifiers: cocoa, keyEquivalent: equiv)
    }

    private static let keyCodes: [String: (UInt32, String)] = {
        var m: [String: (UInt32, String)] = [:]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
            ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal), ("[", kVK_ANSI_LeftBracket), ("]", kVK_ANSI_RightBracket),
            (";", kVK_ANSI_Semicolon), ("'", kVK_ANSI_Quote), (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period),
            ("/", kVK_ANSI_Slash), ("`", kVK_ANSI_Grave), ("\\", kVK_ANSI_Backslash),
        ]
        for (k, v) in letters { m[k] = (UInt32(v), k) }
        m["space"]  = (UInt32(kVK_Space), " ")
        m["return"] = (UInt32(kVK_Return), "\r")
        m["enter"]  = (UInt32(kVK_Return), "\r")
        m["escape"] = (UInt32(kVK_Escape), "\u{1B}")
        m["esc"]    = (UInt32(kVK_Escape), "\u{1B}")
        m["tab"]    = (UInt32(kVK_Tab), "\t")
        m["up"]     = (UInt32(kVK_UpArrow), String(UnicodeScalar(NSUpArrowFunctionKey)!))
        m["down"]   = (UInt32(kVK_DownArrow), String(UnicodeScalar(NSDownArrowFunctionKey)!))
        m["left"]   = (UInt32(kVK_LeftArrow), String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        m["right"]  = (UInt32(kVK_RightArrow), String(UnicodeScalar(NSRightArrowFunctionKey)!))
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, v) in fkeys.enumerated() {
            m["f\(i + 1)"] = (UInt32(v), String(UnicodeScalar(NSF1FunctionKey + i)!))
        }
        return m
    }()
}

final class HotKeys {
    static let file = WhipRunner.folder.appendingPathComponent("hotkeys.json")

    private(set) var combos: [HotAction: KeyCombo] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x45484E47      // 'EHNG'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.handlers[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    // MARK: 설정 파일

    static func loadCombos() -> [HotAction: String] {
        let fm = FileManager.default
        try? fm.createDirectory(at: WhipRunner.folder, withIntermediateDirectories: true)
        var out: [HotAction: String] = [:]
        for a in HotAction.allCases { out[a] = a.defaultCombo }
        if let data = try? Data(contentsOf: file),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            for (k, v) in dict { if let a = HotAction(rawValue: k) { out[a] = v } }
        } else if !fm.fileExists(atPath: file.path) {
            let lines = HotAction.allCases.map { "  \"\($0.rawValue)\": \"\($0.defaultCombo)\"" }
            let text = "{\n" + lines.joined(separator: ",\n") + "\n}\n"
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        return out
    }

    /// 파일을 읽어 전부 다시 등록한다. 돌려주는 값은 못 읽은 항목.
    @discardableResult
    func reload(actions: [HotAction: () -> Void]) -> [HotAction: String] {
        for r in refs { UnregisterEventHotKey(r) }
        refs = []
        handlers = [:]
        combos = [:]
        var bad: [HotAction: String] = [:]
        let texts = Self.loadCombos()
        for (i, a) in HotAction.allCases.enumerated() {
            let text = texts[a] ?? ""
            if text.isEmpty { continue }
            guard let c = KeyCombo.parse(text) else { bad[a] = text; continue }
            var ref: EventHotKeyRef?
            let hk = EventHotKeyID(signature: Self.signature, id: UInt32(i + 1))
            let st = RegisterEventHotKey(c.keyCode, c.carbonModifiers, hk, GetApplicationEventTarget(), 0, &ref)
            guard st == noErr, let ref = ref else { bad[a] = text + t(" (failed to register)"); continue }
            refs.append(ref)
            handlers[UInt32(i + 1)] = actions[a]
            combos[a] = c
        }
        return bad
    }
}
