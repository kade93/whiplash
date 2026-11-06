# Whiplash 개인정보 처리방침 / Privacy Policy

최종 수정: 2026-11-06

## 한국어

Whiplash는 개인정보를 수집하지 않습니다.

- 앱은 사용자의 Mac에서 실행 중인 프로세스 목록을 운영체제로부터 읽기 전용으로 조회합니다.
- Claude Code 세션 정보는 사용자가 허용한 홈 폴더 안의 `.claude` 세션 파일을 읽기 전용으로 조회합니다.
- 세션에 메시지를 보낼 때(직접 배포판)는 Claude Code가 로컬에 제공하는 소켓과 토큰을 사용하며, 토큰을 저장하거나 기록하지 않습니다.
- 앱은 기본적으로 네트워크에 접속하지 않습니다. 사용자가 「당근밭 보기」(남은 쿼터 표시)를 켠 경우에만, 직접 배포판이
  키체인의 Claude Code 로그인 토큰을 읽어 Anthropic의 사용량 조회 API(`api.anthropic.com/api/oauth/usage`)를 5분마다 호출합니다.
  이는 Claude Code의 `/usage` 명령과 같은 조회이며, 토큰은 요청에만 사용하고 저장·기록하지 않습니다. 그 외 어떤 정보도 외부로 전송하지 않으며
  분석·광고·추적 도구를 사용하지 않습니다. App Store 판은 이 기능이 없고 네트워크에 접속하지 않습니다.
- 설정(창 위치, 단축키, 언어 등)은 사용자의 Mac에만 저장됩니다.

문의: GitHub 저장소 이슈(https://github.com/kade93/whiplash/issues)

## English

Whiplash does not collect any personal data.

- The app reads the list of running processes on your Mac from the operating system, read-only.
- Claude Code session details are read from the `.claude` session files inside the home folder you allowed, read-only.
- When sending a message to a session (direct-download edition), the app uses the local socket and token that Claude Code provides; the token is never stored or logged.
- The app makes no network connections by default. Only when you enable "Show carrots" (remaining quota) does the direct-download
  edition read your Claude Code login token from the Keychain and call Anthropic's usage endpoint
  (`api.anthropic.com/api/oauth/usage`) every 5 minutes — the same check as Claude Code's `/usage` command. The token is used for
  the request only and is never stored or logged. Nothing else is transmitted; no analytics, advertising or tracking.
  The App Store edition does not have this feature and makes no network connections.
- Settings (window positions, hotkeys, language) are stored only on your Mac.

Contact: GitHub issues (https://github.com/kade93/whiplash/issues)
