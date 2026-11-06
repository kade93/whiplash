#!/bin/bash
# Whiplash 배포 패키징.
#
#   ./release.sh devid     → Developer ID 서명 + 공증 → build/Whiplash-<버전>.zip  (앱스토어 밖 직접 배포, 전 기능)
#   ./release.sh appstore  → 샌드박스 + Apple Distribution 서명 → build/Whiplash-<버전>.pkg (앱스토어 업로드용)
#
# 준비물 (한 번만):
#   1. Apple Developer Program 가입 (developer.apple.com)
#   2. Xcode → Settings → Accounts 에서 인증서 만들기:
#        - Developer ID Application          (devid)
#        - Apple Distribution                (appstore)
#        - Mac Installer Distribution        (appstore .pkg 서명)
#   3. App Store Connect 에서 앱 만들기: 번들 ID kr.urbanism.whiplash, 이름 Whiplash
#   4. 프로비저닝 프로파일 (appstore): Mac App Store 용으로 만들어 받아서 embedded.provisionprofile 로 저장
#   5. 공증용 키체인 프로파일 (devid):  xcrun notarytool store-credentials whiplash --apple-id <ID> --team-id <TEAM> --password <앱 암호>
#
# 아래 변수만 채우면 된다.
set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="${TEAM_ID:-}"                                   # 예: AB12CD34EF
DEVID_IDENTITY="${DEVID_IDENTITY:-Developer ID Application: 이름 ($TEAM_ID)}"
APPSTORE_IDENTITY="${APPSTORE_IDENTITY:-Apple Distribution: 이름 ($TEAM_ID)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: 이름 ($TEAM_ID)}"
PROFILE="${PROFILE:-embedded.provisionprofile}"           # appstore 전용
NOTARY_PROFILE="${NOTARY_PROFILE:-whiplash}"               # devid 전용 (notarytool store-credentials 이름)

MODE="${1:-}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP="build/Whiplash.app"

[[ -n "$TEAM_ID" ]] || { echo "TEAM_ID 를 먼저 채우세요 (release.sh 위쪽 또는 환경변수)"; exit 1; }

./build.sh >/dev/null
echo "▸ 빌드 완료 v$VERSION"

case "$MODE" in
  devid)
    # 전 기능판: 샌드박스 없음, 강화된 런타임만. 채찍·Ctrl-C 다 됨.
    cat > build/devid.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
EOF
    codesign --force --deep --options runtime --timestamp --sign "$DEVID_IDENTITY" \
      --entitlements build/devid.entitlements "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    ZIP="build/Whiplash-$VERSION.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "▸ 공증 제출 중… (몇 분)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "▸ 완료: $ZIP  (Gumroad·홈페이지 등에서 바로 배포)"
    ;;
  appstore)
    [[ -f "$PROFILE" ]] || { echo "프로비저닝 프로파일이 없어요: $PROFILE"; exit 1; }
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign --force --deep --timestamp --sign "$APPSTORE_IDENTITY" \
      --entitlements Whiplash.entitlements "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    PKG="build/Whiplash-$VERSION.pkg"
    productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
    echo "▸ 완료: $PKG"
    echo "▸ 올리기: Transporter 앱으로 열거나  xcrun altool --upload-app -f \"$PKG\" -t macos --apiKey <KEY> --apiIssuer <ISSUER>"
    ;;
  *)
    echo "사용법: ./release.sh devid | appstore"
    exit 1
    ;;
esac
