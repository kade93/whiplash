#!/bin/bash
# App Store screenshots (2880×1800) → AppStore/screenshots/
# Runs the built app three times with the snapshot hook (English UI, fake quota) and composes the PNGs with tools/shots.swift.
# Your own preferences (language, view mode, theme) are saved first and restored afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Whiplash.app/Contents/MacOS/Whiplash
[ -x "$APP" ] || ./build.sh
PL=~/Library/Preferences/com.kade.whiplash.plist
TMP=$(mktemp -d)
pkill -x Whiplash 2>/dev/null || true; sleep 1

save() { for k in lang compact hidden roaming caged theme; do echo "$k=$(defaults read "$PL" $k 2>/dev/null || true)"; done > "$TMP/prefs"; }
restore() {
  while IFS='=' read -r k v; do
    [ -z "$v" ] && continue
    case "$k" in lang|theme) defaults write "$PL" "$k" "$v";; *) defaults write "$PL" "$k" -bool "$([ "$v" = 1 ] && echo true || echo false)";; esac
  done < "$TMP/prefs"
  open -a Whiplash 2>/dev/null || true
}
trap restore EXIT
save
defaults write "$PL" lang en; defaults write "$PL" compact -bool false; defaults write "$PL" hidden -bool false; defaults write "$PL" theme glass

run() { # name delay [extra env]
  local name=$1 delay=$2; shift 2
  env WHIPLASH_DEMO=1 WHIPLASH_FAKE_QUOTA=35 WHIPLASH_SNAPSHOT="$TMP/$name.png" WHIPLASH_SNAPSHOT_DELAY="$delay" "$@" "$APP" >/dev/null 2>&1 &
  sleep $((delay + 3)); pkill -x Whiplash 2>/dev/null || true; sleep 1
}
defaults write "$PL" roaming -bool false; defaults write "$PL" caged -bool false; run list 6
defaults write "$PL" roaming -bool true;  defaults write "$PL" caged -bool true;  run field 22
defaults write "$PL" caged -bool false;                                             run roam 7 env WHIPLASH_PROMPT_TEST=1

swiftc -O tools/shots.swift -o "$TMP/shots"
"$TMP/shots" "$TMP" AppStore/screenshots
echo "▸ AppStore/screenshots/ 에 5장"
