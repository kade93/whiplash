import Foundation

// MARK: - 유출 감시 (숨은 기능)
// 에이전트가 방금 한 도구 호출(Bash 명령, 파일 쓰기)을 기록 파일 꼬리에서 읽어, 비밀·개인정보를 공개하거나
// 깃에 올리려는 낌새가 보이면 알린다. 전부 이 맥 안에서 문자열만 본다. 비밀 값 자체는 어디에도 남기지 않는다
// (알림에는 앞 몇 글자만 남기고 가린 문장이 나간다).
// Foundation 만 쓴다 — 규칙만 따로 떼어 시험할 수 있게.

/// 세션 하나에서 잡힌 위험한 짓 한 건
struct SessionRisk: Equatable, Identifiable {
    let id: String          // 도구 호출 id (같은 호출을 두 번 알리지 않게)
    let title: String       // 영어 원문 (화면에 낼 때 번역)
    let detail: String      // 가린 명령·파일 이름
    let at: Date
}

enum LeakGuard {
    // 비밀처럼 생긴 글자들. (문자열을 쪼개 둔 건 이 저장소의 커밋 전 검사가 규칙 자체를 비밀로 착각하지 않게 하려는 것)
    private static let tokenSources: [String] = [
        "sk-" + "ant-[A-Za-z0-9_-]{20,}",                       // Anthropic
        "sk-" + "(?:proj-)?[A-Za-z0-9_-]{32,}",                 // OpenAI 류
        "gh" + "[pousr]_[A-Za-z0-9]{30,}",                      // GitHub 토큰
        "github_" + "pat_[A-Za-z0-9_]{30,}",
        "AK" + "IA[0-9A-Z]{16}",                                // AWS access key
        "AIza[0-9A-Za-z_-]{35}",                                // Google API key
        "xox[baprs]-[A-Za-z0-9-]{10,}",                         // Slack
        "[sr]k_live_[0-9A-Za-z]{20,}",                          // Stripe
        "hooks\\.slack\\.com/services/T[A-Za-z0-9/]{20,}",      // Slack webhook
        "-----BEGIN " + "[A-Z ]*PRIVATE" + " KEY-----",         // 개인 키 블록
    ]
    private static let token = try! NSRegularExpression(pattern: "(?:" + tokenSources.joined(separator: "|") + ")")
    /// 주민등록번호 꼴 (앞 6자리 날짜 + 뒷자리 1~4 로 시작)
    private static let rrn = try! NSRegularExpression(pattern: "(?<![0-9])[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])-[1-4][0-9]{6}(?![0-9])")

    // 깃에 올리면 안 되는 파일 이름
    private static let secretFile = "(?:\\.env(?:\\.(?!example|sample|template|dist)[\\w-]+)*(?![\\w.-])|[\\w./-]*\\.pem\\b|[\\w./-]*\\.p12\\b|[\\w./-]*\\.pfx\\b|[\\w./-]*\\.keystore\\b"
        + "|id_(?:rsa|ed25519|ecdsa)\\b|\\.npmrc\\b|\\.netrc\\b|[\\w./-]*credentials(?:\\.json)?\\b|[\\w./-]*secrets?\\.(?:json|ya?ml|toml)\\b"
        + "|[\\w./-]*service[-_]?account[\\w-]*\\.json\\b|[\\w./-]*\\.mobileprovision\\b|[\\w./-]*\\.provisionprofile\\b|AuthKey_[A-Z0-9]+\\.p8\\b)"
    private static let rules: [(title: String, regex: NSRegularExpression)] = [
        ("Staging a secrets file for git",
         cmd("\\bgit\\s+add\\b[^\\n;&|]*?(?<![\\w.-])" + secretFile)),
        ("Publishing publicly",
         cmd("\\bgh\\s+gist\\s+create\\b[^\\n;&|]*(?:--public|\\s-p\\b)|\\bgh\\s+repo\\s+(?:create\\b[^\\n;&|]*--public|edit\\b[^\\n;&|]*--visibility[= ]+public)|\\bnpm\\s+publish\\b(?![^\\n;&|]*--dry-run)")),
        ("Uploading to a paste or file-sharing site",
         cmd("\\b(?:curl|wget|http|nc)\\b[^\\n;&|]*(?:pastebin\\.com|transfer\\.sh|0x0\\.st|file\\.io|termbin\\.com|ix\\.io|paste\\.rs|dpaste\\.|hastebin\\.)")),
        ("Printing a private key or keychain secret",
         cmd("\\b(?:cat|less|more|head|tail|bat|base64|pbcopy\\s*<|xxd)\\b[^\\n;&|]*(?:id_(?:rsa|ed25519|ecdsa)(?!\\.pub)\\b|[\\w./-]*\\.pem\\b|AuthKey_[A-Z0-9]+\\.p8\\b)"
            + "|\\bsecurity\\s+find-(?:generic|internet)-password\\b[^\\n;&|]*\\s-w\\b")),
    ]
    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    /// 명령 자리에 있을 때만 (줄 처음이나 ; & | ( 뒤). 따옴표 안의 글자·grep 검색어·문서 문장에는 안 걸리게.
    private static func cmd(_ body: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: "(?:^|[;&|(])[ \\t]*(?:sudo[ \\t]+)?(?:" + body + ")", options: [.caseInsensitive, .anchorsMatchLines])
    }
    /// heredoc 본문(<<'EOF' … EOF)은 명령이 아니라 내용물이라 뺀다
    private static let heredoc = try! NSRegularExpression(pattern: "<<-?[ \\t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\\1[^\\n]*\\n[\\s\\S]*?\\n[ \\t]*\\2(?![A-Za-z0-9_])")
    static func commandsOnly(_ s: String) -> String {
        heredoc.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<<heredoc")
    }

    /// 비밀이 들어갈 자리가 맞는 파일 (여기 쓰는 건 정상)
    private static let secretHome = rx("(?:^|/)(?:\\.env[\\w.-]*|[\\w.-]*\\.local|\\.npmrc|\\.netrc|[\\w.-]*credentials[\\w.-]*|[\\w.-]*secrets?[\\w.-]*|[\\w.-]*\\.pem|[\\w.-]*\\.key|[\\w.-]*\\.p8)$")

    private static func has(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// 비밀처럼 생긴 부분을 앞 여섯 글자만 남기고 가린다. 길면 자른다.
    static func redact(_ s: String, limit: Int = 140) -> String {
        var out = s
        for r in [token, rrn] {
            let ms = r.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
            for m in ms {
                guard let range = Range(m.range, in: out) else { continue }
                let head = String(out[range].prefix(6))
                out.replaceSubrange(range, with: head + "…[hidden]")
            }
        }
        let flat = out.replacingOccurrences(of: "\n", with: " ⏎ ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// 도구 호출 하나를 보고 위험하면 (제목, 가린 내용)
    static func inspect(tool: String, input: [String: Any]) -> (title: String, detail: String)? {
        switch tool {
        case "Bash":
            guard let cmd = input["command"] as? String, !cmd.isEmpty else { return nil }
            let bare = commandsOnly(cmd)
            for rule in rules where has(rule.regex, bare) { return (rule.title, redact(bare)) }
            if has(token, cmd) { return ("A secret is written in a command", redact(cmd)) }
            return nil
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? ""
            var text = (input["content"] as? String) ?? ""
            text += "\n" + ((input["new_string"] as? String) ?? "")
            text += "\n" + ((input["new_source"] as? String) ?? "")
            if let edits = input["edits"] as? [[String: Any]] { for e in edits { text += "\n" + ((e["new_string"] as? String) ?? "") } }
            let name = (path as NSString).lastPathComponent
            if has(secretHome, path) { return nil }                       // .env 같은 데 쓰는 건 제자리
            if has(token, text) { return ("Writing a secret into a source file", name) }
            if has(rrn, text) { return ("Writing personal ID numbers into a file", name) }
            return nil
        default:
            return nil
        }
    }

    /// 세션에 보내는 경고 (채찍 대신 이 말이 간다)
    static func warning(title: String, detail: String) -> String {
        "Whiplash guard — stop for a moment. You just did something that can leak secrets or personal data: \(title) (\(detail)). "
        + "Do not commit, push, publish, upload or print secrets, keys, tokens or personal information. "
        + "Undo it now if you can (unstage the file, remove the secret from the code or command, delete the public copy), "
        + "and tell the user plainly what happened and whether a key needs to be rotated. If this was a false alarm, say so in one line and carry on."
    }
}
