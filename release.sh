#!/bin/bash
# Whiplash 배포 패키징.
#
#   ./release.sh appstore  → Xcode 프로젝트(xcodegen) 로 아카이브 → 앱스토어용 서명 → App Store Connect 에 바로 업로드
#   ./release.sh devid     → Developer ID 서명 + 공증 → build/Whiplash-<버전>.zip  (앱스토어 밖 직접 배포, 전 기능)
#
# appstore 준비물 (한 번만):
#   1. Xcode → Settings → Accounts 에 Apple ID 로그인 (팀 S79N2P4242). 인증서·프로파일은 xcodebuild 가 알아서 만든다
#      (-allowProvisioningUpdates). 안 만들어지면 Accounts → Manage Certificates → + 에서 Apple Distribution,
#      Mac Installer Distribution 을 직접 추가.
#   2. brew install xcodegen
#   3. App Store Connect 앱: 이름 "Whiplash: AI Agent Critters", 번들 ID com.kade.whiplash, App ID 6832438273 (2026-11-09 생성됨)
#   업로드만 건너뛰고 .pkg 만 만들려면:  EXPORT_ONLY=1 ./release.sh appstore
#
# devid 준비물:
#   1. Xcode Accounts → Manage Certificates → Developer ID Application
#   2. 공증용 키체인 프로파일:  xcrun notarytool store-credentials whiplash --apple-id <ID> --team-id <TEAM> --password <앱 암호>
#   3. TEAM_ID 환경변수 (또는 아래 기본값)
set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="${TEAM_ID:-S79N2P4242}"
DEVID_IDENTITY="${DEVID_IDENTITY:-Developer ID Application: Kade Yoon ($TEAM_ID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-whiplash}"               # devid 전용 (notarytool store-credentials 이름)

MODE="${1:-}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP="build/Whiplash.app"

case "$MODE" in
  appstore)
    command -v xcodegen >/dev/null || { echo "xcodegen 이 없어요:  brew install xcodegen"; exit 1; }
    xcodegen generate >/dev/null
    ARCHIVE="build/Whiplash.xcarchive"
    rm -rf "$ARCHIVE" build/export
    echo "▸ 아카이브 v$VERSION…"
    xcodebuild -project Whiplash.xcodeproj -scheme Whiplash -configuration Release \
      -derivedDataPath build/DerivedData -archivePath "$ARCHIVE" -allowProvisioningUpdates archive -quiet
    OPTS=ExportOptions.plist
    if [[ -n "${EXPORT_ONLY:-}" ]]; then
      sed 's#<string>upload</string>#<string>export</string>#' ExportOptions.plist > build/ExportOptions-local.plist
      OPTS=build/ExportOptions-local.plist
    fi
    echo "▸ 앱스토어 서명 + $([[ -n "${EXPORT_ONLY:-}" ]] && echo '.pkg 내보내기' || echo 'App Store Connect 업로드')…"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" -exportPath build/export -allowProvisioningUpdates
    [[ -n "${EXPORT_ONLY:-}" ]] && echo "▸ 완료: build/export/" || echo "▸ 올라갔어요. App Store Connect ▸ 버전 1.0 ▸ 빌드 에서 고르고 심사에 추가."
    ;;
  devid)
    ./build.sh >/dev/null
    echo "▸ 빌드 완료 v$VERSION"
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
  *)
    echo "사용법: ./release.sh appstore | devid"
    exit 1
    ;;
esac
