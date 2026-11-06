# Whiplash Remote (iPhone · iPad · Apple Watch)

Crack the whip from your pocket. Flick the phone like a whip (the Big Bang Theory "whip app" move), snap your wrist with the Watch, or tap the big button: every idle agent on your Mac gets whipped, and the phone plays the crack instantly.

## How it works

- Whiplash on the Mac advertises `_whiplash._udp` on the local network when **Settings ▸ Whip with your body ▸ Accept iPhone / iPad / Apple Watch remote** is on.
- The iPhone/iPad app finds every Mac running Whiplash on the same Wi‑Fi and sends one UDP line to all of them: `whipall`, `whip`, `flick <g>`, `ping`.
- The Watch app detects the wrist snap with Core Motion and relays it to the phone with WatchConnectivity; the phone forwards it to the Mac.
- A flick is a user-acceleration spike over 2.6 g followed by a stop within 150 ms. Shaking or walking does not trigger it.

## Build

```bash
brew install xcodegen
cd WhiplashRemote && xcodegen generate
open WhiplashRemote.xcodeproj
```

In Xcode set your team under Signing & Capabilities for both targets, then run `WhiplashRemote` on your iPhone (the Watch app installs with it). Requires iOS 17 / watchOS 10. No account is needed inside the app.

The project file is generated from `project.yml` and is not committed.

## Protocol (for other devices)

UDP to port 47777 on the Mac, one line per datagram:

| Line | Effect |
|---|---|
| `whipall` | Whip every idle session |
| `whip` | Whip one random idle session |
| `flick 4.2` | Log the flick strength (g); send `whipall` after it |
| `ping` | Mac replies `pong` |

Anything that can send a UDP packet on the local network can be a remote: a Shortcut, a Stream Deck, a second Mac.

---

# Whiplash Remote (아이폰 · 아이패드 · 애플워치)

주머니에서 채찍질. 빅뱅이론의 "채찍 앱"처럼 폰을 휙 휘두르거나, 워치를 찬 손목을 튕기거나, 큰 버튼을 누르면 맥의 쉬는 에이전트 전부가 맞고 폰에서 바로 「화츅!」 소리가 나요.

- 맥의 Whiplash에서 **설정 ▸ 몸으로 때리기 ▸ 아이폰·아이패드·애플워치 리모트 받기**를 켜면 같은 Wi‑Fi에서 찾을 수 있어요.
- 폰 앱은 같은 네트워크의 Whiplash 맥을 전부 찾아 한 번에 보내요.
- 워치는 손목 스냅을 폰으로 넘기고, 폰이 맥에 전달해요.

빌드는 위 영어 절과 같아요: `xcodegen generate` → Xcode에서 팀 지정 → 아이폰에 설치(워치 앱은 같이 들어감). iOS 17 / watchOS 10 이상.
