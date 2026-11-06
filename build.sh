#!/bin/bash
# Whiplash 빌드.  ./build.sh            → build/Whiplash.app 만들기
#               ./build.sh --install  → ~/Applications 에 넣고 바로 실행
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift 컴파일러가 없어요. 터미널에서 먼저 실행하세요:  xcode-select --install"
  exit 1
fi

APP="build/Whiplash.app"
ARCH="$(uname -m)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 컴파일 ($ARCH)…"
swiftc -O -parse-as-library \
  -target "$ARCH-apple-macos13.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Whiplash"

cp Info.plist "$APP/Contents/Info.plist"
cp PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
cp Resources/*.wav "$APP/Contents/Resources/"
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
if [[ "${1:-}" == "--sandbox" ]]; then
  # 앱스토어판처럼 샌드박스 안에서 돌려 보기 (임시 서명)
  codesign --force --sign - --entitlements Whiplash.entitlements "$APP"
  echo "▸ 샌드박스 서명함 (로컬 테스트용)"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "▸ 완료: $APP"

if [[ "${1:-}" == "--install" ]]; then
  # /Applications 에 쓸 수 있으면 거기(파인더「응용 프로그램」에 보임), 아니면 ~/Applications
  DEST="/Applications"
  [[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  pkill -x Eohang 2>/dev/null || true   # 옛 이름 (설치된 적 있으면)
  pkill -x Whiplash 2>/dev/null || true
  rm -rf "$HOME/Applications/Eohang.app" "$HOME/Applications/A장관리.app" "$HOME/Applications/Whiplash.app" "/Applications/Whiplash.app" 2>/dev/null || true
  cp -R "$APP" "$DEST/"
  open "$DEST/Whiplash.app"
  echo "▸ $DEST/Whiplash.app 실행함"
fi
