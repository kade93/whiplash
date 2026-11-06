import Foundation
import Security

// MARK: - 당근밭 = 남은 쿼터
// Claude Code 의 /usage 가 쓰는 것과 같은 조회: 키체인의 Claude Code 로그인 토큰으로
// https://api.anthropic.com/api/oauth/usage 를 읽는다 (5시간·7일 사용률과 리셋 시각).
// 사용자가 「당근밭 보기」를 켰을 때만 동작하고, 토큰은 요청에만 쓰고 저장하지 않는다.

struct Quota: Equatable {
    struct Window: Equatable {
        var key: String              // five_hour · seven_day · seven_day_<model> …
        var utilization: Double      // 0...100
        var resetsAt: Date?
        var remaining: Double { max(0, min(100, 100 - utilization)) }

        /// 짧은 이름: 세션 · 주간 · Fable
        var shortTitle: String {
            switch key {
            case "five_hour": return t("세션")
            case "seven_day": return t("주간")
            default:
                if key.hasPrefix("seven_day_") { return Quota.modelName(String(key.dropFirst("seven_day_".count))) }
                return key.replacingOccurrences(of: "_", with: " ")
            }
        }
        /// 긴 이름: 세션 (5시간) · 주간 (모든 모델) · 주간 · Fable
        var title: String {
            switch key {
            case "five_hour": return t("세션 (5시간)")
            case "seven_day": return t("주간 (모든 모델)")
            default: return key.hasPrefix("seven_day_") ? t("주간 · ") + shortTitle : shortTitle
            }
        }
    }
    var windows: [Window]
    var fetchedAt: Date
    var error: String? = nil

    var fiveHour: Window? { windows.first { $0.key == "five_hour" } }
    var sevenDay: Window? { windows.first { $0.key == "seven_day" } }
    /// 모델별 주간 창 등 나머지 (Fable, Opus, Sonnet …)
    var extras: [Window] { windows.filter { $0.key != "five_hour" && $0.key != "seven_day" } }
    var exhausted: Bool { (fiveHour?.utilization ?? 0) >= 100 || (sevenDay?.utilization ?? 0) >= 100 }

    static func modelName(_ raw: String) -> String {
        let s = raw.replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// 한 줄 요약: 🥕 남은 쿼터 25% · 주간 55% · Fable 70% · 2시간 뒤
    var summary: String {
        guard let five = fiveHour else { return t("🥕 남은 쿼터 조회 중…") }
        if exhausted { return t("🥕 쿼터 다 씀 · 파업!") }
        var parts = [tf("🥕 남은 쿼터 %d%%", Int(five.remaining))]
        if let w = sevenDay { parts.append(tf("주간 %d%%", Int(w.remaining))) }
        for w in extras { parts.append("\(w.shortTitle) \(Int(w.remaining))%") }
        if let r = five.resetsAt { parts.append(fmtAgoFuture(r)) }
        return parts.joined(separator: " · ")
    }
}

enum QuotaReader {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let queue = DispatchQueue(label: "kr.urbanism.whiplash.quota", qos: .utility)

    enum Failure: Error, LocalizedError {
        case noToken, denied, http(Int), parse, network(String)
        var errorDescription: String? {
            switch self {
            case .noToken:         return t("키체인에 Claude Code 로그인 정보가 없어요 — Claude Code 에서 /login 먼저")
            case .denied:          return t("키체인 접근을 거부했어요 — 「당근밭 보기」를 껐다 켜고 「항상 허용」")
            case .http(let c):     return tf("사용량 조회 실패 (HTTP %d)", c)
            case .parse:           return t("사용량 응답을 못 읽었어요")
            case .network(let s):  return tf("사용량 조회 실패: %@", s)
            }
        }
    }

    static func fetch(completion: @escaping (Result<Quota, Failure>) -> Void) {
        if let fake = ProcessInfo.processInfo.environment["WHIPLASH_FAKE_QUOTA"], let u = Double(fake) {   // 개발용
            let q = Quota(windows: [.init(key: "five_hour", utilization: u, resetsAt: Date().addingTimeInterval(3600 * 2.3)),
                                    .init(key: "seven_day", utilization: u * 0.6, resetsAt: Date().addingTimeInterval(86400 * 3)),
                                    .init(key: "seven_day_fable", utilization: u * 0.85, resetsAt: Date().addingTimeInterval(86400 * 3))], fetchedAt: Date())
            DispatchQueue.main.async { completion(.success(q)) }
            return
        }
        queue.async {
            let token: String
            switch accessToken() {
            case .success(let tk): token = tk
            case .failure(let f): DispatchQueue.main.async { completion(.failure(f)) }; return
            }
            var req = URLRequest(url: endpoint)
            req.httpMethod = "GET"
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Whiplash/0.2", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15
            URLSession.shared.dataTask(with: req) { data, resp, err in
                let result: Result<Quota, Failure>
                if let err = err {
                    result = .failure(.network(err.localizedDescription))
                } else if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    result = .failure(.http(http.statusCode))
                } else if let data = data, let q = parse(data) {
                    result = .success(q)
                } else {
                    result = .failure(.parse)
                }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    /// 키체인 항목 「Claude Code-credentials」(Claude Code 가 로그인할 때 넣음) → claudeAiOauth.accessToken
    /// 처음 읽을 때 macOS 가 허용 창을 띄운다. 토큰은 메모리에서만 쓴다.
    private static func accessToken() -> Result<String, Failure> {
        // Claude Code 가 키체인을 못 쓸 때 쓰는 파일이 있으면 그걸 먼저 — 키체인 암호 창이 안 뜬다
        let file = (Paths.home as NSString).appendingPathComponent(".claude/.credentials.json")
        if let data = FileManager.default.contents(atPath: file),
           let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let oauth = j["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty { return .success(token) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // 사용자가 키체인 허용 창에서 「허용 안 함」·취소를 누르면 여기로 온다
        if status == errSecAuthFailed || status == errSecUserCanceled || status == errSecInteractionNotAllowed { return .failure(.denied) }
        guard status == errSecSuccess,
              let data = item as? Data,
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = j["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .failure(.noToken) }
        return .success(token)
    }

    private static func parse(_ data: Data) -> Quota? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func window(_ key: String) -> Quota.Window? {
            guard let w = j[key] as? [String: Any], w["utilization"] != nil else { return nil }
            let u = (w["utilization"] as? Double) ?? (w["utilization"] as? Int).map(Double.init) ?? 0
            var reset: Date? = nil
            if let s = w["resets_at"] as? String {
                let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = f.date(from: s) ?? { let g = ISO8601DateFormatter(); return g.date(from: s) }()
            } else if let n = w["resets_at"] as? Double {
                reset = Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
            }
            return Quota.Window(key: key, utilization: u, resetsAt: reset)
        }
        // five_hour, seven_day 먼저, 그다음 모델별 창 (seven_day_opus 같은 것) 이름순
        let order = ["five_hour", "seven_day"]
        let rest = j.keys.filter { !order.contains($0) && j[$0] is [String: Any] }.sorted()
        let windows = (order + rest).compactMap(window)
        guard !windows.isEmpty else { return nil }
        return Quota(windows: windows, fetchedAt: Date())
    }
}
