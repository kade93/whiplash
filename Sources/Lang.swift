import Foundation

// MARK: - 언어 (한국어 · English · 日本語)
// 코드의 UI 문자열은 전부 한국어로 쓰고 t("…") 로 감싼다. 표에 없으면 한국어가 그대로 나온다.
// 형식 문자열은 tf("…%d…", 값) — %@ %d %.1f 는 String(format:) 규칙.

enum Lang: String, CaseIterable {
    case ko, en, ja

    var title: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    static var current: Lang = {
        if let saved = UserDefaults.standard.string(forKey: "lang"), let l = Lang(rawValue: saved) { return l }
        let pref = Locale.preferredLanguages.first ?? "ko"
        if pref.hasPrefix("ja") { return .ja }
        if pref.hasPrefix("ko") { return .ko }
        return .en
    }() {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "lang") }
    }
}

func t(_ ko: String) -> String {
    guard Lang.current != .ko, let row = L10n.table[ko] else { return ko }
    return Lang.current == .en ? row.0 : row.1
}

func tf(_ ko: String, _ args: CVarArg...) -> String {
    String(format: t(ko), locale: nil, arguments: args)
}

enum L10n {
    /// 한국어 → (English, 日本語)
    static let table: [String: (String, String)] = [
        // 메뉴 막대 · 앱 메뉴
        "Whiplash — 누르면 메뉴": ("Whiplash — click for menu", "Whiplash — クリックでメニュー"),
        "채찍질 창 보이기": ("Show Whiplash window", "Whiplashウィンドウを表示"),
        "Whiplash 숨기기": ("Hide Whiplash", "Whiplashを隠す"),
        "Whiplash 종료": ("Quit Whiplash", "Whiplashを終了"),
        "Whiplash 닫기": ("Quit Whiplash", "Whiplashを終了"),
        "지금 돌아가는 에이전트가 없어요": ("No agents running right now", "動いているエージェントはいません"),
        "%d마리 · %d 일하는 중 · %d 내 차례": ("%d critters · %d working · %d need you", "%d匹 · %d 作業中 · %d あなたの番"),
        "모두 숨기기": ("Hide all", "すべて隠す"),
        "풀어놓기 — 화면 돌아다니기": ("Let loose — roam the screen", "放す — 画面を歩き回る"),
        "작게 풀어놓기 (이름표 없이)": ("Roam small (no name tags)", "小さく放す（名札なし）"),
        "당근밭에 박아두기": ("Plant in the carrot field", "ニンジン畑に植える"),
        "이리 와 — 커서 자리로 모이기": ("Come here — gather at the cursor", "おいで — カーソルに集合"),
        "쉬는 애 아무나 채찍": ("Whip any idle one", "休んでる子を誰でも鞭"),
        "켜짐 — %@ 까지 · %d분마다 · %d번 때림": ("On — until %@ · every %d min · %d whips", "オン — %@ まで · %d分ごと · %d回"),
        "꺼짐": ("Off", "オフ"),
        "1시간 동안": ("For 1 hour", "1時間"),
        "3시간 동안": ("For 3 hours", "3時間"),
        "퇴근(18시)까지": ("Until 6 PM", "18時まで"),
        "자정까지": ("Until midnight", "深夜0時まで"),
        "아침 9시까지": ("Until 9 AM", "朝9時まで"),
        "끄기": ("Turn off", "オフにする"),
        "%d분마다": ("Every %d min", "%d分ごと"),
        "채찍 문구 편집…": ("Edit whip words…", "鞭の文句を編集…"),
        "오토 채찍질 ⚡ %@ 까지": ("Auto-whip ⚡ until %@", "オート鞭 ⚡ %@ まで"),
        "오토 채찍질": ("Auto-whip", "オート鞭"),
        "풀어놓을 때 채찍질 창도 보기": ("Show list while roaming (both at once)", "放している間もリストを表示（同時表示）"),
        "Dock 에 아이콘 보이기": ("Show icon in Dock", "Dockにアイコンを表示"),
        "⌥ 누른 채로만 채찍 (오작동 방지)": ("Whip only while holding ⌥ (avoid accidents)", "⌥を押している時だけ鞭（誤動作防止）"),
        "캐릭터 뒤 물빛 칸": ("Water tile behind critters", "キャラの後ろに水色タイル"),
        "채찍질 창으로 보기": ("Show as window", "ウィンドウで表示"),
        "작게 보기": ("Compact view", "コンパクト表示"),
        "크게 보기": ("Full view", "フル表示"),
        "항상 맨 위에": ("Always on top", "常に最前面"),
        "로그인할 때 열기": ("Open at login", "ログイン時に開く"),
        "홈 폴더 접근 다시 고르기…": ("Re-pick home folder access…", "ホームフォルダのアクセスを選び直す…"),
        "홈 폴더 접근 허용… (세션 정보 보기)": ("Allow home folder access… (to see sessions)", "ホームフォルダのアクセスを許可…（セッション情報用）"),
        "채찍 일감 편집…": ("Edit whip tasks…", "鞭タスクを編集…"),
        "채찍 일감 다시 읽기": ("Reload whip tasks", "鞭タスクを再読込"),
        "채찍 결과 폴더 열기": ("Open whip results folder", "鞭の結果フォルダを開く"),
        "단축키 편집…": ("Edit hotkeys…", "ショートカットを編集…"),
        "단축키 다시 읽기": ("Reload hotkeys", "ショートカットを再読込"),
        "언어": ("Language", "言語"),
        "모두 숨기기 (메뉴 막대 채찍으로 되돌림)": ("Hide all (bring back from the menu bar whip)", "すべて隠す（メニューバーの鞭から戻す）"),
        "앱 아이콘으로 보기": ("Show app icons", "アプリアイコンで表示"),
        "저장공간 다시 재기": ("Rescan storage", "ストレージを再計測"),
        "채찍질 설정": ("Whiplash settings", "Whiplash設定"),

        // 크리터 · 우리
        "Claude (꺼짐) · 휘두르면 깨워요": ("Claude (off) · swing to wake", "Claude（オフ）· 振って起こす"),
        "Claude (꺼짐)": ("Claude (off)", "Claude（オフ）"),
        "당근밭 · %d마리": ("Carrot field · %d", "ニンジン畑 · %d匹"),
        "뽑아주기": ("Pull out", "抜く"),
        "끌어서 옮길 수 있어요. 애들은 여기 자기 자리에 박혀 있어요.": ("Drag to move. Each one stays planted in its spot.", "ドラッグで移動。みんな自分の場所に植わっています。"),
        "당근밭에서 뽑기": ("Pull out of the field", "畑から抜く"),
        "크게 풀어놓기": ("Roam large", "大きく放す"),
        "작게 풀어놓기": ("Roam small", "小さく放す"),
        "채찍질 창으로 모으기": ("Gather into the window", "ウィンドウに集める"),

        // 단축키
        "모두 숨기기 / 보이기": ("Hide / show all", "すべて隠す / 表示"),
        "풀어놓기 / 채찍질 창": ("Roam / window", "放す / ウィンドウ"),
        "작게 / 크게": ("Small / large", "小 / 大"),
        "당근밭에 박기 / 뽑기": ("Plant / pull out", "植える / 抜く"),
        "이리 와 (커서 자리로 모이기)": ("Come here (gather at cursor)", "おいで（カーソルに集合）"),
        "채찍질 창 보이기 / 숨기기": ("Both at once on / off", "同時表示 オン / オフ"),
        " (등록 실패)": (" (failed to register)", "（登録失敗）"),

        // 지시 보내기
        "이 세션은 메시지 소켓이 없어요": ("This session has no message socket", "このセッションにはメッセージソケットがありません"),
        "세션 키 파일을 못 읽었어요": ("Couldn't read the session key file", "セッションのキーファイルを読めません"),
        "세션에 연결 못 함 (errno %d)": ("Couldn't connect to the session (errno %d)", "セッションに接続できません (errno %d)"),
        "보내다 끊김 (errno %d)": ("Dropped while sending (errno %d)", "送信中に切断 (errno %d)"),
        "세션이 거절함: %@": ("Session refused: %@", "セッションが拒否: %@"),
        "앱스토어판에서는 보낼 수 없어요 — 전체 기능판에서 돼요": ("Not available in the App Store edition — use the full edition", "App Store版では送れません — フル版で使えます"),
        "전체 기능판 받기… (채찍 메시지·지시 보내기·오토 채찍)": ("Get the full edition… (whip messages, send instruction, auto-whip)", "フル版を入手…（鞭メッセージ・指示送信・オート鞭）"),
        "전체 기능판 받기…": ("Get the full edition…", "フル版を入手…"),
        "Claude 앱 세션": ("Claude app session", "Claudeアプリのセッション"),
        "터미널 세션": ("Terminal session", "ターミナルのセッション"),
        "지시를 쳐서 바로 보내요 (⏎ 보내기 · esc 닫기)": ("Type an instruction and send (⏎ send · esc close)", "指示を入力して送信（⏎ 送信 · esc 閉じる）"),
        "일하는 중이라 지금 턴이 끝난 뒤에 읽어요": ("Busy — reads this after the current turn", "作業中 — 今のターンが終わったら読みます"),
        "쉬는 중 · 바로 읽어요": ("Idle · reads right away", "休憩中 · すぐ読みます"),
        "보내는 중…": ("Sending…", "送信中…"),
        "보냈어요 ✓": ("Sent ✓", "送りました ✓"),
        "창 앞으로": ("Bring window to front", "ウィンドウを前へ"),

        // 화냄 (존댓말 → 반말)
        "말을 해야 하죠!!!": ("You need to tell me what to do!!", "決めてくださいよ!!!"),
        "말을 해야 할 거 아냐!!": ("Just say something already!!", "お前が決めろよ!!"),
        "할 일을 주셔야죠!!": ("I need something to do!!", "仕事をくださいよ!!"),
        "할 일을 줘야지!!": ("Give me work then!!", "仕事くれよ!!"),
        "왜 때리세요!!": ("Why are you hitting me?!", "なんで叩くんですか!!"),
        "왜 때려!!": ("Stop hitting me!!", "叩くなって!!"),
        "꺼져 있어요": ("off", "オフ"),

        // 상태
        "앱": ("app", "アプリ"),
        "터미널": ("Terminal", "ターミナル"),
        "Claude Code 세션 정보(~/.claude)를 읽으려면 홈 폴더 접근을 허용해 주세요. 읽기만 해요.": ("To read Claude Code session info (~/.claude), please allow access to your home folder. Read-only.", "Claude Codeのセッション情報（~/.claude）を読むため、ホームフォルダへのアクセスを許可してください。読み取りのみです。"),
        "허용": ("Allow", "許可"),
        "지시 읽는 중": ("Reading the prompt", "指示を読んでいる"),
        "생각하는 중": ("Thinking", "考え中"),
        "답하는 중": ("Answering", "返答中"),
        "읽는 중": ("Reading", "読んでいる"),
        "고치는 중": ("Editing", "編集中"),
        "쓰는 중": ("Writing", "書いている"),
        "실행 중": ("Running", "実行中"),
        "찾는 중": ("Searching", "検索中"),
        "부하 시키는 중": ("Delegating", "部下に任せ中"),
        "검색 중": ("Web searching", "ウェブ検索中"),
        "웹 읽는 중": ("Reading the web", "ウェブを読んでいる"),
        "물어보는 중": ("Asking you", "質問中"),
        "계획 승인 기다림": ("Waiting for plan approval", "計画の承認待ち"),
        "할 일 적는 중": ("Writing todos", "TODOを書いている"),
        " 중": (" in progress", "中"),
        "방금": ("just now", "たった今"),
        "%d분": ("%dm", "%d分"),
        "%d시간 %d분": ("%dh %dm", "%d時間%d分"),
        "%d일": ("%dd", "%d日"),
        "Claude 앱": ("Claude app", "Claudeアプリ"),
        "기타 에이전트": ("Other agent", "その他のエージェント"),
        "꽃게": ("crab", "カニ"), "모래게": ("sand crab", "スナガニ"), "해파리": ("jellyfish", "クラゲ"),
        "복어": ("pufferfish", "フグ"), "오징어": ("squid", "イカ"), "고래": ("whale", "クジラ"), "물방울": ("droplet", "しずく"),

        // 채찍질 창
        "%.1f코어": ("%.1f cores", "%.1fコア"),
        "이 창만 닫기 — 캐릭터는 계속 돌아다녀요 (메뉴 막대 채찍 → 풀어놓을 때 채찍질 창도 보기)": ("Close this window only — critters keep roaming (menu bar whip → Keep the window while roaming)", "このウィンドウだけ閉じる — キャラは歩き続けます（メニューバーの鞭 → 放している間もウィンドウを表示）"),
        "닫기 — 메뉴 막대 채찍에서 다시 열어요": ("Close — reopen from the menu bar whip", "閉じる — メニューバーの鞭から再表示"),
        "모두 쉬는 중": ("All resting", "全員休憩中"),
        "%d마리 · %d 일하는 중": ("%d critters · %d working", "%d匹 · %d 作業中"),
        "· %d 내 차례": ("· %d need you", "· %d あなたの番"),
        "· %d 과부하": ("· %d overloaded", "· %d 過負荷"),
        "오토 채찍질 켜짐 · %d분마다 쉬는 세션에 「계속해」 · 지금까지 %d번": ("Auto-whip on · idle sessions get a nudge every %d min · %d so far", "オート鞭オン · %d分ごとに休憩中のセッションへ · これまで%d回"),
        "%@ / 전체 %@": ("%@ / total %@", "%@ / 全体 %@"),
        "메모리": ("Memory", "メモリ"),
        "색 = 에이전트, 회색 = 다른 앱, 빈 칸 = 남은 자원": ("Color = agents, gray = other apps, empty = free", "色 = エージェント、灰 = 他のアプリ、空 = 空き"),
        "%@ 데이터 폴더\n": ("%@ data folder\n", "%@ データフォルダ\n"),
        "디스크": ("Disk", "ディスク"),
        "여유 %@": ("%@ free", "空き %@"),
        "에이전트 데이터 폴더 합계 %@ · 30분마다 다시 잼": ("Agent data folders total %@ · rescanned every 30 min", "エージェントのデータフォルダ合計 %@ · 30分ごとに再計測"),
        "채찍질 자체 CPU %@ · %@": ("Whiplash itself CPU %@ · %@", "Whiplash自身 CPU %@ · %@"),
        "자는 중 · 휘두르면 깨워요": ("Asleep · swing to wake", "寝てる · 振って起こす"),
        "과부하 · CPU %@ · %@": ("Overloaded · CPU %@ · %@", "過負荷 · CPU %@ · %@"),
        "채찍 맞고 %@": ("Whipped: %@", "鞭を受けて %@"),
        "일하는 중": ("Working", "作業中"),
        "쉬는 중": ("Resting", "休憩中"),
        "%@ · %d개": ("%@ · %d procs", "%@ · %d個"),
        "답 기다리는 중 · %@": ("Your turn · %@", "返事待ち · %@"),
        "물어보고 기다림 · %@": ("Asked you · %@", "質問中 · %@"),
        "허락 기다리는 중 · %@": ("Needs permission · %@", "許可待ち · %@"),
        "쉬는 중 · %@": ("Resting · %@", "休憩中 · %@"),
        "휙휙 → 앱 켜기\n오른쪽 클릭 → 폴더 골라 터미널": ("Swing → open app\nRight-click → pick folder, Terminal", "振る → アプリ起動\n右クリック → フォルダを選んでターミナル"),
        "마지막 지시: ": ("Last prompt: ", "最後の指示: "),
        "세션 시작 %@ 전 · %@": ("Session started %@ ago · %@", "セッション開始 %@ 前 · %@"),
        "먹이값 %@": ("Feed cost %@", "エサ代 %@"),
        "고친 줄 +%d −%d": ("Lines +%d −%d", "変更行 +%d −%d"),
        "%@ · PID %d · 프로세스 %d개 · CPU는 맥 전체 대비": ("%@ · PID %d · %d procs · CPU vs whole Mac", "%@ · PID %d · プロセス%d個 · CPUはMac全体比"),
        "캐릭터 위에서 마우스를 휙휙 흔들면 앱을 앞으로 불러와요": ("Swing the mouse over it to bring the app forward", "キャラの上でマウスを振るとアプリを前に出します"),
        "캐릭터 위에서 마우스를 휙휙 흔들면 채찍질 (읽기만 하는 일감 하나) · 오른쪽 클릭으로 골라서": ("Swing the mouse over it to whip · right-click to pick a task", "キャラの上でマウスを振ると鞭 · 右クリックでタスクを選択"),
        "Claude 앱 열기": ("Open Claude app", "Claudeアプリを開く"),
        "터미널에서 claude 열기": ("Open claude in Terminal", "ターミナルでclaudeを開く"),
        "홈 폴더에서": ("In home folder", "ホームフォルダで"),
        "채찍 — 일감 골라 시키기": ("Whip — pick a task", "鞭 — タスクを選んで任せる"),
        "채찍 면역 풀기": ("Remove whip immunity", "鞭の免疫を解除"),
        "채찍 면역 (손·오토 채찍 다 안 맞음)": ("Whip immunity (no manual or auto whips)", "鞭の免疫（手動・オート両方効かない）"),
        "제자리 클릭 → 지시 보내기": ("Click in place → send instruction", "その場でクリック → 指示を送る"),
        "폴더 열기": ("Open folder", "フォルダを開く"),
        "마지막 지시 복사": ("Copy last prompt", "最後の指示をコピー"),
        "대화 기록 파일 열기": ("Open transcript file", "会話ログを開く"),
        "하던 일 멈추기 (Ctrl-C)": ("Stop current work (Ctrl-C)", "作業を止める (Ctrl-C)"),
        "%@ · %@\n%@\nCPU %@ · 메모리 %@": ("%@ · %@\n%@\nCPU %@ · Memory %@", "%@ · %@\n%@\nCPU %@ · メモリ %@"),
        "\n마우스를 휙휙 흔들거나 눌러서 채찍질": ("\nSwing the mouse or click to whip", "\nマウスを振るかクリックで鞭"),
        "짝!": ("CRACK!", "ピシッ!"),
        "아야": ("Ouch", "いたっ"),
        "결과": ("Result", "結果"),
        "실패": ("Failed", "失敗"),
        "눌러서 결과 열기": ("Click to open the result", "クリックで結果を開く"),

        // 당근밭 · 파업
        "당근밭": ("Carrots", "ニンジン畑"),
        "7일": ("7 days", "7日"),
        "조회 중…": ("Checking…", "確認中…"),
        "다 뽑힘 · 파업!": ("All gone · strike!", "全部なくなった · ストライキ!"),
        "%d%% 남음 · %@": ("%d%% left · %@", "%d%% 残り · %@"),
        "%d%% 씀 · %@": ("%d%% used · %@", "%d%% 使用 · %@"),
        "지금": ("now", "今"),
        "%d분 뒤": ("in %dm", "%d分後"),
        "%d시간 %d분 뒤": ("in %dh %dm", "%d時間%d分後"),
        "%d일 뒤": ("in %dd", "%d日後"),
        "✊ 파업 중 · %@ 까지": ("✊ On strike · until %@", "✊ ストライキ中 · %@ まで"),
        "· %d 파업": ("· %d on strike", "· %d ストライキ"),
        "쿼터가 없어요!!": ("I'm out of quota!!", "クォータがありません!!"),
        "쿼터 없다고!!": ("No quota, I said!!", "クォータないって!!"),
        "당근밭 보기 — 남은 쿼터 (Claude 로그인 키체인 읽기)": ("Show carrots — remaining quota (reads Claude login from Keychain)", "ニンジン畑を表示 — 残りクォータ（キーチェーンのClaudeログインを読む）"),
        "🥕 당근밭 다 뽑힘 · 파업!": ("🥕 Carrots all gone · strike!", "🥕 ニンジン全滅 · ストライキ!"),
        "🥕 당근밭 %d%% 남음 · %@": ("🥕 Carrots %d%% left · %@", "🥕 ニンジン %d%% 残り · %@"),
        "5시간 창 남은 쿼터 = 남은 당근. 다 뽑히면 애들이 파업해요. 5분마다 Claude 사용량을 조회해요 (키체인의 Claude Code 로그인으로).": ("Remaining 5-hour quota = remaining carrots. When they're gone, the critters strike. Usage is checked every 5 minutes using your Claude Code login from the Keychain.", "5時間枠の残りクォータ = 残りニンジン。なくなるとみんなストライキ。5分ごとにキーチェーンのClaude Codeログインで使用量を確認します。"),
        "키체인에서 Claude Code 로그인 정보를 못 읽었어요": ("Couldn't read the Claude Code login from the Keychain", "キーチェーンからClaude Codeのログイン情報を読めません"),
        "사용량 조회 실패 (HTTP %d)": ("Usage check failed (HTTP %d)", "使用量の確認に失敗 (HTTP %d)"),
        "사용량 응답을 못 읽었어요": ("Couldn't read the usage response", "使用量の応答を読めません"),
        "사용량 조회 실패: %@": ("Usage check failed: %@", "使用量の確認に失敗: %@"),

        // 채찍 일감
        "다음 할 일 찾아와": ("Find the next tasks", "次のタスクを探す"),
        "이 프로젝트를 훑어보고 지금 바로 손댈 만한 다음 작업 3가지를 우선순위, 이유, 관련 파일과 함께 제안해 줘.": ("Skim this project and propose the next 3 tasks worth doing right now, with priority, reasoning and related files.", "このプロジェクトを見て、今すぐ取りかかれる次のタスクを3つ、優先度・理由・関連ファイルと一緒に提案して。"),
        "코드 리뷰해": ("Review the code", "コードレビュー"),
        "가장 최근에 수정된 파일들 위주로 코드를 리뷰해서 버그 가능성, 빠진 예외 처리, 개선점을 심각한 순서로 정리해 줘.": ("Review the most recently modified files for likely bugs, missing error handling and improvements, ordered by severity.", "最近変更されたファイルを中心にレビューして、バグの可能性・抜けている例外処理・改善点を深刻な順にまとめて。"),
        "TODO 수거해": ("Collect TODOs", "TODOを集める"),
        "프로젝트 안의 TODO, FIXME, HACK 주석을 모두 찾아 파일과 줄 번호와 함께 묶어 정리하고, 처리할 순서를 제안해 줘.": ("Find every TODO, FIXME and HACK comment with file and line, group them and propose an order to handle them.", "プロジェクト内のTODO・FIXME・HACKコメントをファイルと行番号付きで集めて整理し、対応順を提案して。"),
        "출시 점검해": ("Release checklist", "リリース点検"),
        "이 앱을 앱스토어에 내기 전에 빠진 것(아이콘, 권한 문구, 개인정보 처리방침, 에러 처리, 하드코딩된 키나 비밀번호, 디버그 코드 등)을 점검표로 정리해 줘.": ("Make a checklist of what is missing before shipping to the App Store (icons, permission strings, privacy policy, error handling, hard-coded keys or passwords, debug code).", "App Storeに出す前に足りないもの（アイコン・権限文言・プライバシーポリシー・エラー処理・ハードコードされたキー・デバッグコードなど）をチェックリストにして。"),
        "문서 다듬어": ("Polish the docs", "ドキュメント整備"),
        "README와 기획 문서(SPEC 등)를 실제 코드와 비교해서 틀리거나 빠진 내용을 찾아 고칠 문장을 제안해 줘.": ("Compare README and spec docs against the actual code, find what is wrong or missing, and propose corrected sentences.", "READMEや企画書（SPECなど）を実際のコードと比べ、間違いや抜けを見つけて修正文を提案して。"),
        "\n\n(규칙: 파일을 만들거나 고치거나 지우지 말고, 명령도 실행하지 말고 읽기만 해. 답은 한국어 마크다운으로 짧고 구체적으로.)": ("\n\n(Rules: do not create, edit or delete files and do not run commands — read only. Answer in short, concrete Markdown in English.)", "\n\n（ルール: ファイルの作成・編集・削除も、コマンド実行もせず読むだけ。答えは短く具体的な日本語のMarkdownで。）"),
        "찰싹! (Whiplash) 하던 일 이어서 해. 끝났으면 다음 할 일 하나 골라서 해.": ("Whack! (Whiplash) Keep going with what you were doing. If you're done, pick the next thing and do it.", "ピシッ! (Whiplash) やりかけの作業を続けて。終わってたら次の仕事を一つ選んでやって。"),
        "%@ 실행 파일을 못 찾았어요": ("Couldn't find the %@ executable", "%@ の実行ファイルが見つかりません"),
        "# %@\n\n- 에이전트: %@\n- 프로젝트: %@\n- 시작: %@\n\n---\n\n": ("# %@\n\n- Agent: %@\n- Project: %@\n- Started: %@\n\n---\n\n", "# %@\n\n- エージェント: %@\n- プロジェクト: %@\n- 開始: %@\n\n---\n\n"),
        "끝까지 못 했어요 (종료 코드 %d) · 로그: %@": ("Didn't finish (exit code %d) · log: %@", "最後までできませんでした（終了コード %d）· ログ: %@"),
        "중간에 멈췄어요 (시간 초과 또는 종료)": ("Stopped midway (timeout or killed)", "途中で止まりました（タイムアウトまたは終了）"),
        "실행 실패: %@": ("Failed to run: %@", "実行失敗: %@"),
    ]
}
