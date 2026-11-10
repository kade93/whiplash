# Whiplash Remote (iPhone · iPad · Apple Watch)

Crack the whip from your pocket. Flick the phone like a whip (the Big Bang Theory "whip app" move), snap your wrist with the Watch, or tap the big button: every idle agent on your Mac gets whipped, and the phone plays the crack instantly.

## How it works

- Whiplash on the Mac advertises `_whiplash._udp` on the local network when **Settings ▸ Whip with your body ▸ Accept iPhone / iPad / Apple Watch remote** is on.
- The iPhone/iPad app finds every Mac running Whiplash on the same Wi‑Fi and sends one UDP line to all of them: `whipall`, `whip`, `flick <g>`, `ping`.
- The Watch app detects the wrist snap with Core Motion and relays it to the phone with WatchConnectivity; the phone forwards it to the Mac.
- A flick is a user-acceleration spike over 2.6 g followed by a stop within 150 ms. Shaking or walking does not trigger it.

## Setup, step by step

1. **Mac:** Whiplash ▸ Settings ▸ Whip with your body ▸ *Accept iPhone / iPad / Apple Watch remote* → on. Allow "local network" when macOS asks. The status line under the switch says "Listening on port 47777" once it is up.
2. **Build the phone app** (not on the App Store yet):
   ```bash
   brew install xcodegen
   cd WhiplashRemote && xcodegen generate
   open WhiplashRemote.xcodeproj
   ```
   The team is preset in `project.yml`; if Xcode complains, pick yours under Signing & Capabilities for both targets. Select the `WhiplashRemote` scheme, your iPhone as the destination, and Run. The Watch app installs together with it (Watch ▸ My Watch ▸ Whiplash Remote if it does not appear). Requires iOS 17 / watchOS 10. No account inside the app.
3. **Same Wi‑Fi.** Open the app on the phone; it lists every Mac that is running Whiplash with the remote switched on, and sends to all of them. If the list is empty, check that both devices are on the same network and that the Mac switch is on (AP isolation on guest networks blocks Bonjour).
4. **Whip.** Flick the phone like a whip, snap the wrist wearing the Watch, or tap the big button. The phone plays the crack itself the moment it detects the flick, so the feedback is instant even before the Mac reacts. The Mac answers with what it did ("Whack! 3 whipped", "Nobody to whip — everyone's busy"), shown under the button, so you can tell it landed even with the sound off.
5. **Pick a critter.** The phone lists every session on the Mac (name, working / resting / waiting / on strike) with a ⚡ whip and a 🥕 treat button per row, plus "Treat all". The list refreshes every 4 seconds.

## Tuning

A flick is a user-acceleration (gravity removed) peak over **2.0 g** followed by the hand stopping (under 1.0 g) within **250 ms**, with a 0.9 s cooldown — see `Shared/Flick.swift`. Walking is ~0.3 g and a shake ~1.5 g. These values were chosen from typical sensor figures, not a large test group; if your flicks are missed, lower `threshold` to 1.6; if walking triggers it, raise it to 2.6. The Watch relays through the phone with WatchConnectivity, so the phone must be nearby and awake.

The project file is generated from `project.yml` and is not committed.

## Protocol (for other devices)

UDP to port 47777 on the Mac, one line per datagram:

| Line | Effect | Reply |
|---|---|---|
| `whipall` | Whip every idle session | `ok whipped 3` / `ok nobody to whip` |
| `whip` | Whip one random idle session | `ok whipped one` |
| `whip <id>` | Whip that session (ids come from `list`) | `ok whipped <name>` / `ok <name> is immune` |
| `treatall` | Give every working session a treat | `ok treated 2` / `ok nobody to treat` |
| `treat <id>` | Treat that session | `ok treated <name>` |
| `list` | Session list | `list` then one line per session: `<id>␉<name>␉<state>␉<kind>` (state: working / resting / waiting / strike) |
| `flick 4.2` | Log the flick strength (g); send `whipall` after it | none |
| `ping` | Connection check | `pong` |

Anything that can send a UDP packet on the local network can be a remote: a Shortcut, a Stream Deck, a second Mac.

---

# Whiplash Remote (아이폰 · 아이패드 · 애플워치)

주머니에서 채찍질. 빅뱅이론의 "채찍 앱"처럼 폰을 휙 휘두르거나, 워치를 찬 손목을 튕기거나, 큰 버튼을 누르면 맥의 쉬는 에이전트 전부가 맞고 폰에서 바로 「화츅!」 소리가 나요.

- 맥의 Whiplash에서 **설정 ▸ 몸으로 때리기 ▸ 아이폰·아이패드·애플워치 리모트 받기**를 켜면 같은 Wi‑Fi에서 찾을 수 있어요.
- 폰 앱은 같은 네트워크의 Whiplash 맥을 전부 찾아 한 번에 보내요.
- 워치는 손목 스냅을 폰으로 넘기고, 폰이 맥에 전달해요.

준비 순서는 위 영어 절과 같아요.
1. 맥: Settings ▸ 몸으로 때리기 ▸ 아이폰·아이패드·애플워치 리모트 받기 켜기. "로컬 네트워크" 허용.
2. 폰 앱 빌드: `cd WhiplashRemote && xcodegen generate` → Xcode에서 아이폰에 Run (워치 앱은 같이 설치, 팀은 project.yml에 들어 있음). iOS 17 / watchOS 10 이상. 아직 앱스토어엔 없어요.
3. 폰과 맥을 같은 Wi‑Fi에. 앱이 맥을 못 찾으면 맥 쪽 스위치와 네트워크(게스트 와이파이는 Bonjour를 막아요)를 확인.
4. 폰을 휙, 워치 찬 손목을 튕기거나, 큰 버튼. 폰이 먼저 소리를 내고 맥이 뒤따라요. 맥이 뭘 했는지("Whack! 3 whipped", "Nobody to whip")가 버튼 아래에 떠서 소리를 못 들어도 알 수 있어요.
5. 폰에 맥의 세션 목록(이름·일하는 중/쉬는 중/내 차례/파업)이 뜨고, 줄마다 ⚡채찍·🥕간식 버튼이 있어요. 「Treat all」로 일하는 애 전부 간식.

휘두름 기준은 2.0g 넘고 250ms 안에 멈추기(`Shared/Flick.swift`). 많은 사람에게 시험한 값은 아니라서 잘 안 잡히면 1.6으로 낮추고, 걷다가 터지면 올리면 돼요.
