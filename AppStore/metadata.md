# Whiplash — 앱스토어 심사 제출 자료 초안

App Store Connect 에 붙여 넣을 글과 체크리스트. 바꿔도 되는 건 전부 바꿔도 됨.

## 기본

| 항목 | 값 |
|---|---|
| 이름 | Whiplash |
| 부제 (30자) | 내 AI 에이전트들을 채찍질하는 어항 |
| 부제 (EN) | Whip your AI agents into shape |
| 번들 ID | kr.urbanism.whiplash |
| 카테고리 | 유틸리티 (보조: 엔터테인먼트) |
| 가격 | 무료 (인앱 결제 없음) |
| 연령 | 4+ |
| 저작권 | © 2026 Kade |
| 지원 URL | https://urbanism.kr/whiplash (만들어야 함) |
| 개인정보 처리방침 URL | https://urbanism.kr/whiplash/privacy (아래 글 올리면 됨) |
| 암호화 | 사용 안 함 (ITSAppUsesNonExemptEncryption = NO, plist에 들어 있음) |

## 설명 (KR)

맥에서 돌아가는 AI 코딩 에이전트(Claude Code, Codex, Cursor, Gemini CLI…)가 지금 뭘 하는지,
누가 내 답을 기다리는지, CPU·메모리를 얼마나 물고 있는지 — 픽셀 캐릭터들로 한눈에.

- 세션마다 캐릭터 하나. 일하면 연장을 들고 휘두르고, 쉬면 잠들고, 내 차례면 폴짝 뛰어요.
- 읽는 중엔 책, 고치는 중엔 연필, 명령 실행 중엔 망치. 지금 하는 일이 그대로 보여요.
- 답·질문·허락을 기다리는 세션은 노란 말풍선. 여러 세션을 돌릴 때 어디로 돌아가야 할지 바로 알 수 있어요.
- 과부하(CPU·메모리)면 빨개지고 김이 나요.
- 풀어놓기: 캐릭터들이 바탕화면을 돌아다녀요. 작게, 우리에 가두기, 모두 숨기기, 전역 단축키.
- 채찍질: 쉬는 캐릭터 위에서 마우스를 휙휙 흔들면 「짝!」.

Claude Code 세션 정보는 홈 폴더의 `.claude` 를 읽기만 해요. 어디로도 보내지 않아요.

## 설명 (EN)

See what your AI coding agents (Claude Code, Codex, Cursor, Gemini CLI…) are doing right now —
who's working, who's waiting for you, who's eating your CPU — as tiny pixel critters.

- One critter per session. Working ones swing a tool, idle ones sleep, the ones waiting on you hop.
- A book while reading, a pencil while editing, a hammer while running commands.
- Sessions waiting for your reply, a question or a permission get a yellow speech bubble.
- Overloaded? They turn red and steam.
- Let them roam your desktop, shrink them, pen them up, hide them all, global hotkeys.
- Crack the whip: swing your mouse over an idle critter.

Reads your `~/.claude` session files locally. Nothing leaves your Mac.

## 키워드 (100자)

claude code,codex,cursor,gemini,ai agent,monitor,cpu,pixel,pet,desktop,tamagotchi,개발,에이전트,모니터

## 새로운 기능 (1.0)

첫 출시.

## 스크린샷 (필수: 1280×800 또는 2880×1800, 최소 1장, 최대 10장)

찍을 장면:
1. 어항 창 — 세션 여러 개, 내 차례 노란 줄, 과부하 빨간 줄
2. 풀어놓기 — 바탕화면 위를 걷는 캐릭터들 (이름표 포함)
3. 우리에 가두기
4. 채찍질 순간 「짝!」 (StrikeTile 애니메이션 중)
5. 메뉴 막대 채찍 메뉴 + 단축키

찍는 법: `EOHANG_SNAPSHOT=/경로.png` 로 실행하면 창 자체를 PNG로 저장. 바탕화면 포함 장면은 ⇧⌘5.

## 심사 노트 (Review Notes)

Whiplash is a desktop companion that visualises locally running AI coding agents.

- It lists processes with `proc_listallpids`/`proc_pidinfo` (read-only) to find agent processes
  (Claude Code, Codex, Cursor, Gemini CLI) and shows their CPU/memory.
- To show session titles and status it reads `~/.claude/sessions/*.json` and the tail of
  `~/.claude/projects/**/*.jsonl`. The user grants access to their home folder once via NSOpenPanel
  (security-scoped bookmark). Nothing is written there, nothing is uploaded anywhere.
- Global hotkeys use RegisterEventHotKey (no Accessibility permission needed).
- No accounts, no network, no analytics.

Reviewer tip: without Claude Code installed the aquarium shows "no agents running"; the roaming
critters and menus can still be exercised. A demo video is attached.

## 개인정보 처리방침 (올릴 글)

Whiplash는 개인정보를 수집하지 않습니다. 앱은 사용자의 Mac에서 실행 중인 프로세스 목록과,
사용자가 허용한 홈 폴더 안의 `.claude` 세션 파일을 읽기만 하며, 어떤 정보도 외부 서버로 전송하지 않습니다.
설정(창 위치, 단축키 등)은 Mac 안에만 저장됩니다.

Whiplash does not collect any personal data. It reads the list of running processes on your Mac and,
with your permission, the `.claude` session files in your home folder. Nothing is transmitted anywhere.
Settings are stored only on your Mac.

## 제출 전 체크리스트

- [ ] Apple Developer Program 가입, 인증서 3종 (release.sh 머리말)
- [ ] App Store Connect 에 앱 생성 (번들 ID kr.urbanism.whiplash)
- [x] `./build.sh --sandbox` 로 샌드박스판 로컬 테스트 (2026-11-05): 프로세스 목록·CPU·메모리 OK (sysctl + taskinfo), 홈 폴더 허용 → 세션 제목 붙는지는 직접 확인
- [ ] `./release.sh appstore` → .pkg → Transporter 업로드
- [ ] 스크린샷 5장, 1024 아이콘(assets/icon-1024.png — 자동으로 들어감)
- [ ] 지원 URL·개인정보 URL 페이지 올리기
- [ ] 심사 노트 + 데모 영상 첨부 (에이전트 없는 환경에서 심사할 수 있으니 꼭)

## 샌드박스 실험 결과 (2026-11-06)

- 프로세스 목록·CPU·메모리: `sysctl kern.proc` + `PROC_PIDTASKINFO` 로 **동작**.
- `~/.claude` 읽기: 홈 폴더를 NSOpenPanel 로 한 번 허용받으면 **동작**.
- 세션 소켓(`/tmp/cc-socks/<pid>.sock`) connect: **차단** (errno 1). `network.client` 와
  `temporary-exception.files.absolute-path.read-write` 로 `/tmp/cc-socks/`·`/private/tmp/cc-socks/` 를 열어도 똑같이 차단.
  → 앱스토어판에서는 채찍 메시지·지시 보내기·오토 채찍을 제공할 수 없다. 창 앞으로 가져오기로 대체.
- 보조 에이전트(`claude -p`) 실행: 샌드박스를 물려받아 동작 불가. 제공 안 함.
- 결론: **앱스토어 = 무료 관람·관리판**, **전체 기능 = Developer ID 공증 직접 배포(무료 다운로드)**. 두 판 모두 `release.sh` 로 만든다.

## 앱스토어판과 직접 배포판 차이

| | 앱스토어 (샌드박스) | 직접 배포 (Developer ID) |
|---|---|---|
| 세션 보기·돌아다니기·단축키 | ○ | ○ |
| 채찍질 | 창 앞으로 불러오기만 | 세션에 「계속해」 메시지 (소켓 없으면 보조 에이전트) |
| 지시 보내기 · 오토 채찍 | × | ○ |
| 하던 일 멈추기 (Ctrl-C) | × | ○ |
| ~/.claude 접근 | 처음 한 번 홈 폴더 허용 | 바로 |
| 메모리 숫자 | resident size (taskinfo) | phys footprint (활성 상태 보기와 같음) |
