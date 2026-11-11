# Whiplash — the fun parts

Everything in Whiplash that exists only because it made us laugh. Use this list for the App Store demo, screenshots, release notes and future skins. English first, Korean below.

## The signature move: line them up, crack once

1. Press ⌃⌥G (**Come here**). Every critter walks to your pointer and stands in a single row (up to ten; more than that forms a grid).
2. Swing the mouse once, fast, across the row. Every critter you pass over gets whipped at the same time.
3. The sounds stack: one crack, then a round of "ouch!" voices offset by a few dozen milliseconds, louder the more critters you hit.
4. Click any critter and type the next job. Done.

**Trackpad feel.** Every hit also gives a haptic "thunk" on the trackpad, one per critter when several are hit. And you can whip with a two-finger flick: hover a critter and flick sideways; keep the flick going (about 260 px) and the whole row it stands in gets whipped.

No pointer gymnastics needed for the row: the per-critter whip (hover, then two swipes) is for picking one out. ⌃⌥⇧W does the same thing from the keyboard: **Whip everyone idle**.

## Whip with your body

Four more ways to crack it, all opt-in under Settings ▸ Whip with your body, all of them whipping every idle critter at once:

- **AirPods head flick.** Wearing AirPods, snap your head sideways. The Mac reads the head-motion sensor (macOS 14+).
- **Camera hand swing.** Swing your hand across the camera like you're holding a whip. Only hand joints are tracked, nothing is recorded.
- **Say "whoosh-crack!"** Make the whip sound with your mouth. The mic listens for a sharp burst only.
- **iPhone / iPad / Apple Watch.** The Whiplash Remote app: flick the phone like the Big Bang Theory whip app, snap your wrist with the Watch, or press the big button. The phone plays the crack instantly and every Mac running Whiplash on the Wi‑Fi gets whipped.

## Carrot and stick

- **Treats.** Pet a critter slowly (three slow strokes) or right-click → Give a treat: it gets a praise prompt, hops, and says "Yum!" with a carrot and a heart. ⌃⌥T treats everyone who is working. Fast strokes are the whip, slow ones are the treat — same hand, opposite mood.
- **Megaphone.** ⌃⌥B opens a box that sends one message to every Claude session at once. Handy for "stop and summarize" or "everyone: ship it".

## Critters and what they carry

| Agent | Creature |
|---|---|
| Claude Code (terminal) | Crab |
| Claude app | Sand crab |
| Codex | Axolotl |
| Cursor | Squid |
| Gemini CLI | Pufferfish |
| Antigravity | Whale |
| Anything else | Blob |

Working critters swing a tool that matches what the session is doing right now: a book while reading, a pencil while editing, a hammer while running a command, a magnifying glass while searching, a globe for web, a thought bubble while thinking, a speech bubble while answering. A session that is delegating to sub-agents holds a tiny whip of its own. Every working critter drags a ball and chain on one ankle.

## Reactions you can trigger

- **Whip streak.** Whip the same critter again within 8 seconds and the sound escalates: whip 1, whip 2, whip 3. The voices were synthesized to sound like a small creature, not a person.
- **It talks back.** Whip a critter that is waiting on *you* (it asked a question, needs permission, or finished and is idle) and it answers in words. The second hit is polite ("You need to say something!!"), the third drops the politeness ("Say something already!!"). In Korean it switches from 존댓말 to 반말. It also refuses to deliver the whip message while it is angry: there is nothing to do.
- **Immunity shield.** Right-click → Whip immunity. The critter gets a 🛡 and whips bounce off with a "tink". Useful for the one session that is actually doing fine.
- **Strike.** When the Claude quota runs out, every Claude critter drops its tool, picks up a picket sign and refuses to work. Whipping a striker only gets you "There's no quota!!" and a buzz. The strike ends when the quota resets or the session answers again.
- **Starving.** In the carrot field each critter sits on its own carrot. Carrots are pulled from the right as quota is used (one carrot = 10%). A critter whose carrot is gone gets a 🥕✕ badge, and when a carrot disappears the critter on that seat hops and you hear a crunch.
- **Overloaded.** A session eating more than 1.5 CPU cores or a lot of memory turns red and steams.
- **Your turn.** Critters waiting for you hop every couple of seconds and show !, ? or ✋ above the head.

## Hidden and quiet

- **Claude (off).** When no Claude is running, a translucent ghost crab appears. Whip it to launch the Claude app; right-click to open `claude` in Terminal in one of your recent project folders.
- **Platform walking.** Roaming critters walk along the top edges of your other windows, as if they were ledges.
- **They never overlap.** Gathering, planting, roaming: critters always keep their distance.
- **Vanishing act.** When you start working for real (fast mouse for ~3 seconds, or typing), the critters fade out so they never block a click. Eight quiet seconds later they return.
- **Feed cost.** The money column is labelled "feed cost". Tokens are what the critters eat.
- **Auto-whip bell.** When a scheduled auto-whip period ends, a glass "ding" plays, like a shift ending.
- **Whip words.** The default message delivered on a whip is `Whack! (Whiplash) Keep going with what you were doing. If you're done, pick the next thing and do it.` You can edit it; the "Whiplash" tag tells the session who nudged it.
- **Terminal theme.** Five themes; the "Terminal" one turns the window into green phosphor.
- **Menu bar.** The icon up there is a crab holding a whip.

## Ideas for skins (after launch)

- Seasonal costumes for the critters (hats, scarves).
- Alternative whip sounds (bamboo switch, wet towel, rubber chicken).
- Carrot field variants: fish tank, office cubicles, galley oars.
- A "boss" skin where the critter you whip most often grows a crown.

## Hidden: the leak guard

Not in any menu. Whiplash reads the tail of each Claude Code session's transcript anyway (that is how it knows who is reading or editing), so it also looks at the tool calls an agent just made. If one looks like it is about to leak a secret or personal data, the agent gets caught in the act:

- an angry buzz, the critter takes a whip, and a panel appears at the top right naming the agent and what it did, with the secret itself hidden (only the first six characters are shown);
- in the direct-download edition the session also receives a stern prompt: stop, undo it, tell the user what happened and whether a key needs rotating;
- buttons: **Stop it (Ctrl-C)**, **Go to the agent**, **Leave it**.

What trips it:

| It sees | Example |
|---|---|
| A secrets file being staged for git | `git add .env`, `git add certs/server.pem`, a service-account JSON, an SSH private key |
| Something being published | `gh gist create --public`, `gh repo edit --visibility public`, `npm publish` |
| An upload to a paste or file-drop site | `curl -F f=@dump.sql https://0x0.st` |
| A private key or Keychain secret being printed | `cat ~/.ssh/id_rsa`, `security find-generic-password … -w` |
| A token typed straight into a command | an API key inside a `curl` header or a git remote URL |
| A secret or a resident registration number written into a source file | an API key hard-coded in `config.ts` |

What it leaves alone: text that only mentions such a command (inside quotes, a search term, a heredoc body), `git add -A`, `.env.example`, writing keys into `.env` or `*.local` (that is where they belong), public keys, `npm publish --dry-run`. Only calls from the last five minutes are looked at, each one once. Everything happens on your Mac by matching text; nothing is stored or sent, apart from the warning prompt to the session itself.

It is a tripwire, not a scanner: it sees commands and file writes, not what is inside a commit, so it will miss things and will sometimes cry wolf. Turn it down or off with a hidden setting:

```bash
defaults write com.kade.whiplash leakGuard alert   # panel only, no prompt to the session
defaults write com.kade.whiplash leakGuard off     # nothing
defaults delete com.kade.whiplash leakGuard        # back to the default (panel + prompt)
```

---

# Whiplash — 재미 요소 정리

웃기려고 넣은 것들 전부. 앱스토어 데모·스크린샷·릴리스 노트·나중 스킨 작업에 쓰는 목록.

## 대표 장면: 줄 세워 놓고 한 번에 후려치기

1. ⌃⌥G 「이리 와」. 캐릭터들이 포인터 쪽으로 걸어와 **한 줄로** 섭니다 (10마리까지, 그 이상은 격자).
2. 그 줄 위로 마우스를 한 번 빠르게 휘두릅니다. 지나간 캐릭터 전부가 동시에 맞아요.
3. 소리가 겹칩니다: 「짝」 한 번 뒤에 「아야」가 수십 밀리초씩 어긋나서 돌림노래처럼, 마릿수가 많을수록 더 크게.
4. 아무 캐릭터나 클릭해서 다음 일을 칩니다. 끝.

**트랙패드 손맛.** 맞을 때마다 트랙패드가 「툭」 하고 울려요(여러 마리면 연타). 두 손가락 튕김으로도 때릴 수 있어요: 캐릭터 위에서 옆으로 휙 튕기면 그 애, 길게(260px쯤) 튕기면 그 애가 선 줄 전부.

한 마리만 골라 때릴 땐 전처럼 머문 뒤 두 번 흔들면 되고, 키보드로는 ⌃⌥⇧W 「쉬는 애 전부 채찍」.

## 몸으로 때리기

Settings ▸ 몸으로 때리기에서 켜는 네 가지. 전부 쉬는 애 전원이 한 번에 맞아요.

- **에어팟 고개 휙.** 에어팟 끼고 고개를 휙 돌리기. 머리 움직임 센서를 읽어요(macOS 14 이상).
- **카메라 손 휘두르기.** 카메라 앞에서 채찍 쥔 것처럼 손을 휙. 손 관절만 추적하고 녹화는 없어요.
- **입으로 「화츅!」.** 입으로 채찍 소리 내기. 마이크는 짧은 파열음만 들어요.
- **아이폰·아이패드·애플워치.** Whiplash Remote 앱: 빅뱅이론 채찍 앱처럼 폰을 휙 휘두르거나, 워치 찬 손목을 튕기거나, 큰 버튼. 폰에서 바로 소리가 나고 같은 Wi‑Fi의 Whiplash 맥 전부가 맞아요.

## 채찍과 당근

- **간식.** 캐릭터를 천천히 세 번 쓰다듬거나 오른쪽 클릭 → 간식 주기: 칭찬 프롬프트가 가고, 폴짝 뛰면서 「냠!」과 당근·하트. ⌃⌥T는 일하는 애 전부. 빠르게 쓸면 채찍, 느리게 쓸면 간식.
- **확성기.** ⌃⌥B로 Claude 세션 전부에 같은 말을 한 번에. "다들 멈추고 정리해" 같은 거.

## 캐릭터와 들고 있는 것

Claude Code = 꽃게, Claude 앱 = 모래게, Codex = 우파루파, Cursor = 오징어, Gemini CLI = 복어, Antigravity = 고래, 그 외 = 물방울.

일하는 캐릭터는 지금 하는 일에 맞는 연장을 휘둘러요: 읽는 중엔 책, 고치는 중엔 연필, 명령 실행은 망치, 검색은 돋보기, 웹은 지구본, 생각 중엔 생각 풍선, 답하는 중엔 말풍선. 부하 에이전트를 부리는 세션은 자기도 작은 채찍을 들어요. 일하는 애들은 전부 발목에 쇠공을 달고 있어요.

## 반응

- **연타.** 8초 안에 같은 애를 또 때리면 소리가 1→2→3으로 세져요. 목소리는 사람 말고 작은 생물처럼 합성했어요.
- **말대꾸.** 내 차례인 애(질문했거나, 허락 기다리거나, 다 끝내고 쉬는 애)를 때리면 말로 받아쳐요. 두 번째는 존댓말(「말을 해야 하죠!!!」), 세 번째부터 반말(「말을 해야 할 거 아냐!!」). 화난 동안엔 채찍 메시지도 안 보내요. 시킬 일이 없으니까요.
- **면역 방패.** 오른쪽 클릭 → 채찍 면역. 🛡가 붙고 채찍이 「팅」 하고 튕겨요. 잘하고 있는 한 세션 보호용.
- **파업.** Claude 쿼터가 바닥나면 Claude 캐릭터 전원이 연장을 내려놓고 피켓을 들어요. 파업 중에 때리면 「쿼터가 없어요!!」와 부저 소리뿐. 쿼터가 리셋되거나 세션이 다시 답하면 끝나요.
- **굶기.** 당근밭에선 한 마리가 당근 한 개에 앉아요. 쿼터를 쓸수록 오른쪽부터 뽑히고(당근 1개 = 10%), 자기 당근이 사라진 애는 🥕✕ 배지, 당근이 뽑히는 순간 그 자리 애가 펄쩍 뛰며 아삭 소리.
- **과부하.** CPU 1.5코어 이상이나 메모리를 많이 먹으면 빨개지고 김이 나요.
- **내 차례.** 나를 기다리는 애는 몇 초마다 폴짝 뛰고 머리 위에 !, ?, ✋.

## 숨은 것·조용한 것

- **Claude (꺼짐).** Claude가 하나도 안 돌면 반투명 유령 꽃게가 나타나요. 때리면 Claude 앱이 켜지고, 오른쪽 클릭으로 최근 프로젝트 폴더에서 터미널 claude를 열 수 있어요.
- **창 윗변 걷기.** 돌아다니는 애들은 다른 창의 윗변을 난간처럼 걸어다녀요.
- **절대 안 겹침.** 모이든 심기든 돌아다니든 서로 거리를 지켜요.
- **사라지기.** 본격적으로 일하기 시작하면(마우스 3초 빠르게, 또는 타자) 스르륵 사라져서 클릭을 막지 않아요. 8초 조용하면 돌아와요.
- **먹이값.** 비용 칸 이름이 「먹이값」. 토큰은 얘네 먹이예요.
- **퇴근 종.** 오토 채찍 기간이 끝나면 「딩」 유리 소리. 교대 끝.
- **채찍 문구.** 기본 메시지는 「찰싹! (Whiplash) 하던 일 이어서 해. 끝났으면 다음 할 일 하나 골라서 해.」 바꿀 수 있고, (Whiplash) 꼬리표로 누가 찔렀는지 세션이 알아요.
- **터미널 테마.** 테마 다섯 개 중 「터미널」은 창을 녹색 인광으로 바꿔요.
- **메뉴 막대.** 위에 있는 아이콘은 채찍 든 꽃게예요.

## 출시 뒤 스킨 아이디어

- 계절 코스튬(모자, 목도리).
- 다른 채찍 소리(회초리, 젖은 수건, 고무 닭).
- 당근밭 변형: 어항, 사무실 칸막이, 갤리선 노.
- 가장 많이 맞은 애가 왕관을 쓰는 「보스」 스킨.

## 숨은 기능: 유출 감시

메뉴 어디에도 없습니다. Whiplash는 원래 각 Claude Code 세션 기록의 끝부분을 읽기 때문에(누가 읽는 중이고 고치는 중인지 그걸로 압니다), 에이전트가 방금 한 도구 호출도 같이 봅니다. 비밀이나 개인정보를 흘릴 것 같은 호출이 보이면 현장에서 잡습니다.

- 「부!」 소리와 함께 캐릭터가 채찍을 맞고, 화면 오른쪽 위에 누가 무엇을 했는지 창이 뜹니다. 비밀 값은 앞 여섯 글자만 남기고 가립니다.
- 직접 다운로드판에서는 그 세션에 「멈추고, 되돌리고, 무슨 일이 있었는지와 키를 바꿔야 하는지 사용자에게 말해」라는 경고 프롬프트도 보냅니다.
- 버튼: **멈추기 (Ctrl-C)**, **에이전트에게 가기**, **그냥 두기**.

걸리는 것: 비밀 파일을 깃에 올리기(`git add .env`, `.pem`, 서비스 계정 JSON, SSH 개인 키), 공개 게시(`gh gist create --public`, 레포 공개 전환, `npm publish`), 붙여넣기·파일 공유 사이트 업로드, 개인 키·키체인 비밀 출력, 명령어에 토큰을 그대로 적기, 소스 파일에 비밀이나 주민번호 적기.

안 걸리는 것: 그런 명령을 글자로만 언급한 것(따옴표 안, 검색어, heredoc 본문), `git add -A`, `.env.example`, `.env`·`*.local`에 키 적기(거기가 제자리), 공개 키, `npm publish --dry-run`. 최근 5분 안의 호출만, 한 건당 한 번만 봅니다. 전부 이 맥 안에서 글자만 맞춰 보고, 세션에 보내는 경고 프롬프트 말고는 아무것도 저장하거나 보내지 않습니다.

경보선이지 정밀 검사가 아닙니다. 명령과 파일 쓰기만 보고 커밋 내용은 못 보므로 놓치는 것도 있고 괜히 울리는 것도 있습니다. 끄거나 줄이려면 위 영어 절의 `defaults write com.kade.whiplash leakGuard alert|off` 를 쓰면 됩니다.
