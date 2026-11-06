#!/bin/bash
# 개인정보·비밀 유출 검사.  tools/secrets-check.sh [--staged | --history | 파일...]
#   --staged  : 커밋에 올라갈 파일만 (pre-commit 훅이 씀)
#   --history : 지금까지의 모든 커밋 내용
#   (없음)     : 작업 트리의 추적 파일 전부
# 하나라도 걸리면 1 로 끝난다.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

# 1) 올라가면 안 되는 파일 이름
BAD_NAMES='(^|/)(\.env(\..*)?|hotkeys\.json|whips\.json|whip-words\.txt|.*\.(p12|cer|pem|key|p8|provisionprofile|mobileprovision|jsonl|log|keychain(-db)?))$|(^|/)whips/|(^|/)snap.*\.png$'
# 2) 내용 패턴: API 키·토큰·개인 키·비밀번호, 홈 경로, 이메일
PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]{10,}'                         # Anthropic 키
  'sk-[A-Za-z0-9]{20,}'                               # OpenAI 류
  'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' # GitHub 토큰
  'xox[baprs]-[A-Za-z0-9-]{10,}'                      # Slack
  'AKIA[0-9A-Z]{16}'                                  # AWS
  'AIza[0-9A-Za-z_-]{30,}'                            # Google
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '"?(accessToken|refreshToken|peerToken|api[_-]?key|password|secret)"?[[:space:]]*[:=][[:space:]]*"[^"$][^"]{8,}"'
  'Bearer [A-Za-z0-9._-]{30,}'
  '/Users/[A-Za-z0-9._-]+'                            # 내 홈 경로
  '[A-Za-z0-9._%+-]+@(gmail|naver|daum|kakao|icloud|outlook|hotmail)\.com'
)
ALLOW='noreply@anthropic\.com|users\.noreply\.github\.com|/Users/<|/Users/\$|/Users/me/|/Users/USER'

mode="${1:-tree}"
fail=0
report() { echo "✖ $1"; fail=1; }

if [ "$mode" = "--history" ]; then
  for p in "${PATTERNS[@]}"; do
    hits=$(git log -p --all | grep -nE -e "$p" | grep -vE "$ALLOW" | grep -vE '^[0-9]+:(Author|Co-Authored-By):' | head -5)
    [ -n "$hits" ] && report "히스토리에 패턴 /$p/:" && echo "$hits" | cut -c1-200
  done
  names=$(git log --all --name-only --format= | sort -u | grep -E "$BAD_NAMES")
  [ -n "$names" ] && report "히스토리에 올라간 금지 파일:" && echo "$names"
  [ $fail = 0 ] && echo "✔ 히스토리 깨끗함"
  exit $fail
fi

if [ "$mode" = "--staged" ]; then
  files=$(git diff --cached --name-only --diff-filter=ACMR)
  getter() { git show ":$1"; }
elif [ "$mode" = "tree" ]; then
  files=$(git ls-files)
  getter() { cat "$1"; }
else
  files="$*"
  getter() { cat "$1"; }
fi

for f in $files; do
  if echo "$f" | grep -qE "$BAD_NAMES"; then report "금지 파일: $f"; continue; fi
  case "$f" in *.png|*.wav|*.icns|*.jpg|*.gif) continue;; esac
  for p in "${PATTERNS[@]}"; do
    hits=$(getter "$f" | grep -nE -e "$p" | grep -vE "$ALLOW" | head -3)
    [ -n "$hits" ] && report "$f — /$p/:" && echo "$hits" | cut -c1-200
  done
done
[ $fail = 0 ] && echo "✔ 깨끗함 ($mode)"
exit $fail
