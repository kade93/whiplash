# Whiplash — Privacy Policy / 개인정보 처리방침

Last updated: 2026-11-10

## English

Whiplash does not collect any personal data. There is no account, no analytics, no advertising and no tracking.

- **Processes.** The app reads the list of running processes on your Mac from the operating system, read-only, to show which AI coding agents are running and how much CPU and memory they use.
- **Session files.** Claude Code session details come from the `.claude` session files in your home folder, read-only. In the App Store edition you grant that folder once through the standard macOS open panel; the app never writes there.
- **Sending messages (direct-download edition only).** When you whip or message a session, the app uses the local socket and token that Claude Code provides on your Mac. The token is used for that request only and is never stored or logged.
- **Remaining quota (direct-download edition only).** Only if you turn on "Show remaining quota" does the app read your Claude Code login token from the Keychain and call Anthropic's usage endpoint (`api.anthropic.com/api/oauth/usage`) every 5 minutes, the same check as Claude Code's `/usage` command. Nothing else is sent to any server. The App Store edition does not have this feature.
- **Whip with your body (optional, off by default).** Each trigger works only while its switch is on and asks for its permission when you turn it on:
  - Camera: hand positions are analysed on the Mac in memory to detect a swing. No frames are recorded or saved.
  - Microphone: only the sound level is measured to detect a sharp burst. No audio is recorded.
  - AirPods motion: head-motion readings are used to detect a head flick and are not stored.
  - Local network: the Mac announces itself on your Wi‑Fi (Bonjour `_whiplash._udp`, UDP port 47777) and receives one-line commands from the Whiplash Remote app on your iPhone, iPad or Apple Watch. Nothing leaves your local network.
- **Settings** (window positions, hotkeys, language, which sessions are immune) are stored only on your Mac.

Whiplash Remote (the companion app) sends only those one-line commands over your local network and stores nothing.

Contact: GitHub — https://github.com/kade93

## 한국어

Whiplash는 개인정보를 수집하지 않습니다. 계정도, 분석 도구도, 광고도, 추적도 없습니다.

- **프로세스.** 어떤 AI 코딩 에이전트가 돌고 있고 CPU·메모리를 얼마나 쓰는지 보여 주기 위해, 운영체제로부터 실행 중인 프로세스 목록을 읽기 전용으로 조회합니다.
- **세션 파일.** Claude Code 세션 정보는 홈 폴더 안의 `.claude` 세션 파일을 읽기 전용으로 조회합니다. App Store 판에서는 macOS 표준 열기 패널로 홈 폴더를 한 번 허용하며, 앱은 그곳에 아무것도 쓰지 않습니다.
- **메시지 보내기(직접 다운로드판만).** 세션에 채찍질하거나 메시지를 보낼 때는 Claude Code가 Mac 안에 제공하는 로컬 소켓과 토큰을 사용합니다. 토큰은 그 요청에만 쓰고 저장·기록하지 않습니다.
- **남은 쿼터(직접 다운로드판만).** 「남은 쿼터 보기」를 켠 경우에만 키체인의 Claude Code 로그인 토큰을 읽어 Anthropic 사용량 조회 API(`api.anthropic.com/api/oauth/usage`)를 5분마다 호출합니다. Claude Code의 `/usage` 명령과 같은 조회입니다. 그 외 어떤 서버로도 아무것도 보내지 않습니다. App Store 판에는 이 기능이 없습니다.
- **몸으로 때리기(선택, 기본 꺼짐).** 각 항목은 스위치를 켠 동안에만 동작하며 켤 때 권한을 묻습니다.
  - 카메라: 손 위치를 Mac 안에서 메모리로만 분석해 휘두름을 감지합니다. 영상은 저장하지 않습니다.
  - 마이크: 짧은 파열음을 감지하기 위해 음량만 잽니다. 소리는 녹음하지 않습니다.
  - 에어팟 모션: 고개 휙을 감지하는 데만 쓰고 저장하지 않습니다.
  - 로컬 네트워크: Mac이 Wi‑Fi에 자신을 알리고(Bonjour `_whiplash._udp`, UDP 47777) 아이폰·아이패드·애플워치의 Whiplash Remote 앱에서 한 줄짜리 명령을 받습니다. 로컬 네트워크 밖으로는 아무것도 나가지 않습니다.
- **설정**(창 위치, 단축키, 언어, 면역 세션)은 Mac 안에만 저장됩니다.

Whiplash Remote(동반 앱)는 그 한 줄짜리 명령만 로컬 네트워크로 보내며 아무것도 저장하지 않습니다.

문의: GitHub — https://github.com/kade93
