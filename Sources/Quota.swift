import Foundation
import Security

// MARK: - 당근밭 = 남은 쿼터
// Claude Code 의 /usage 가 쓰는 것과 같은 조회: 키체인의 Claude Code 로그인 토큰으로
// https://api.anthropic.com/api/oauth/usage 를 읽는다 (5시간·7일 사용률과 리셋 시각).
// 사용자가 「당근밭 보기」를 켰을 때만 동작하고, 토큰은 요청에만 쓰고 저장하지 않는다.

struct Quota: Equatable {
    struct Window: Equatable {
        var utilization: Double      // 0...100
        var resetsAt: Date?
        var remaining: Double { max(0, min(100, 100 - utilization)) }
    }
    var fiveHour: Window?
    var sevenDay: Window?
    var fetchedAt: Date
    var error: String? = nil

    var exhausted: Bool { (fiveHour?.utilization ?? 0) >= 100 || (sevenDay?.utilization ?? 0) >= 100 }
}

enum QuotaReader {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let queue = DispatchQueue(label: "kr.urbanism.whiplash.quota", qos: .utility)

    enum Failure: Error, LocalizedError {
        case noToken, http(Int), parse, network(String)
        var errorDescription: String? {
            switch self {
            case .noToken:         return t("키체인에서 Claude Code 로그인 정보를 못 읽었어요")
            case .http(let c):     return tf("사용량 조회 실패 (HTTP %d)", c)
            case .parse:           return t("사용량 응답을 못 읽었어요")
            case .network(let s):  return tf("사용량 조회 실패: %@", s)
            }
        }
    }

    static func fetch(completion: @escaping (Result<Quota, Failure>) -> Void) {
        if let fake = ProcessInfo.processInfo.environment["WHIPLASH_FAKE_QUOTA"], let u = Double(fake) {   // 개발용
            let q = Quota(fiveHour: .init(utilization: u, resetsAt: Date().addingTimeInterval(3600 * 2.3)),
                          sevenDay: .init(utilization: u * 0.6, resetsAt: Date().addingTimeInterval(86400 * 3)), fetchedAt: Date())
            DispatchQueue.main.async { completion(.success(q)) }
            return
        }
        queue.async {
            guard let token = accessToken() else { DispatchQueue.main.async { completion(.failure(.noToken)) }; return }
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
    private static func accessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = j["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private static func parse(_ data: Data) -> Quota? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func window(_ key: String) -> Quota.Window? {
            guard let w = j[key] as? [String: Any] else { return nil }
            let u = (w["utilization"] as? Double) ?? (w["utilization"] as? Int).map(Double.init) ?? 0
            var reset: Date? = nil
            if let s = w["resets_at"] as? String {
                let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = f.date(from: s) ?? { let g = ISO8601DateFormatter(); return g.date(from: s) }()
            } else if let n = w["resets_at"] as? Double {
                reset = Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
            }
            return Quota.Window(utilization: u, resetsAt: reset)
        }
        guard j["five_hour"] != nil || j["seven_day"] != nil else { return nil }
        return Quota(fiveHour: window("five_hour"), sevenDay: window("seven_day"), fetchedAt: Date())
    }
}
