# Whiplash User Guide

Version 0.2 · macOS 13 or later · Apple Silicon / Intel

Whiplash is a desktop utility that monitors and controls AI coding agents running on your Mac (Claude Code, Codex, Cursor, Gemini CLI and others). Each agent session is shown as a character on screen, so you can see at a glance what it is doing, whether it is waiting for you, and how much CPU and memory it uses. You can also send instructions to a session or nudge it back to work.

---

## 1. System requirements

| Item | Requirement |
|---|---|
| Operating system | macOS 13 Ventura or later · Windows 10/11 and Linux (x64) with the separate edition in section 2.3 |
| Processor | Apple Silicon or Intel |
| Supported agents | Claude Code (Terminal or Claude app), Codex CLI/app, Cursor, Gemini CLI, Antigravity, others (opencode, aider, goose) |
| Session details | Claude Code 2.1 or later (versions that write `~/.claude/sessions`) |

Session titles, current activity, waiting state, sending instructions and auto-whip are available for Claude Code sessions only. Other agents show per-process CPU and memory.

## 2. Installation

### 2.1 Direct download (full features)

1. Copy `Whiplash.app` to `/Applications`.
2. On first launch, choose **Open** if macOS asks for confirmation. (Builds signed with a Developer ID and notarized open without additional prompts.)
3. The Whiplash icon appears at the right of the menu bar and monitoring starts.

To build from source you need the Xcode Command Line Tools:

```bash
xcode-select --install
./build.sh --install
```

### 2.2 Mac App Store edition (limited)

The App Store edition runs inside the Apple app sandbox. The following features differ:

| Feature | Direct download | App Store |
|---|---|---|
| Session monitoring, status, resource usage | Yes | Yes (one-time home folder access required) |
| Roaming, pen, hotkeys, menus | Yes | Yes |
| Whip — send a message to the session | Yes | No (brings the window to front instead) |
| Send instruction, auto-whip | Yes | No |
| Stop current work (Ctrl-C) | Yes | No |
| Memory figure | Same as Activity Monitor (phys footprint) | Resident size (approximate) |

On first launch the App Store edition asks for access to your home folder. Choose **Allow** to see session titles and status. The choice is remembered.

### 2.3 Windows and Linux

Whiplash also runs on Windows 10/11 and Linux as a separate app built with Electron (source in `desktop/`). Download it from the
GitHub Releases page of the repository; nothing needs to be installed.

| Platform | File | How to run |
|---|---|---|
| Windows | `Whiplash-<version>-win-x64.zip` | Unzip anywhere and start `Whiplash.exe`. SmartScreen may warn the first time (More info → Run anyway). An optional `.msi` installer is attached when available. |
| Linux | `Whiplash-<version>-linux-x64.AppImage` | `chmod +x` and run. Needs `libfuse2` on some distributions; the `.tar.gz` contains a plain `whiplash` binary instead. |

The Windows and Linux edition has session detection, status, roaming and list views, whip, treats, megaphone, hotkeys and the tray menu.
The whip delivers the prompt to Claude Code through its named pipe (Windows) or Unix socket (Linux), the same way as on macOS.
Not available there: the carrot field and remaining quota, auto-whip, whipping with your body, the iPhone / Watch remote and hiding while you type.
Configuration lives in `%APPDATA%\Whiplash` (Windows) or `~/.config/whiplash` (Linux). See `desktop/README.md` for platform notes (Wayland, tray, WSL).

## 3. Getting started

On first launch a welcome window opens once. It shows the three basic controls and offers two options, both changeable later under **Settings ▸**.

| Option | Description |
|---|---|
| Show remaining quota | Displays the remaining quota as carrots. Turning it on triggers a one-time macOS Keychain prompt (see 5.4). Direct-download edition only. |
| Open at login | Registers Whiplash as a login item. |

In the App Store edition the window has an **Allow home folder…** button that grants access to session information. No other system permission is required in either edition.

Whiplash then automatically:

- detects agent processes (every 2 seconds, or every 15 seconds while the window is hidden),
- reads Claude Code session files (title, activity, running cost),
- shows the menu bar icon and the Dock icon,
- registers global hotkeys.

The default view is **Roaming** (characters walk around the screen). For a list view, choose **Show as window** from the menu bar icon or press ⌃⌥A.

## 4. Screen layout

### 4.1 The Whiplash window (list view)

A borderless window listing sessions and resource usage. Drag anywhere to move it.

| Area | Content |
|---|---|
| Traffic lights | Red: quit Whiplash (⌥-click only hides) / Yellow: minimize to the menu bar; the whip icon or ⌃⌥H brings it back (⌥-click switches compact / full view) / Green: roaming. In compact view they are larger and stacked down the left edge |
| Header | Session count, working, waiting for you, overloaded, auto-whip end time |
| CPU / Memory bars | Color = agents, gray = other apps, empty = free |
| Session row | Character, session title, project folder, running cost, changed lines, current activity, CPU and memory |
| Footer | Agent data folder sizes, free disk space, Whiplash's own usage |

Double-click the window to switch between **Compact view** (characters and bars only, the default) and the full list. In compact view the critters wrap after 10 per row; resize it by its edges: drag the right edge left or right to make it narrower or wider one critter at a time, or drag the bottom edge up or down to change the number of rows; the critters reflow to fit. The bottom-right corner (marked with three small lines) does both. While you drag, the edge follows the pointer like any Mac window and the critters glide into as many columns or rows as fit; when you let go, the window settles snugly around them. Each critter has its session name underneath, coloured by state (**Settings ▸ Show names under critters** turns that off for a denser strip), and the line at the bottom tells you about whichever critter the pointer is over: name, folder and what it is doing right now, such as the file it is editing or the command it is running. With nothing under the pointer it shows the totals. **Settings ▸ Critters per row** (5, 8, 10, 15 or 20) sets the same number.

### 4.2 Roaming

Each session becomes a character in its own transparent window and walks around the screen.

- Working sessions carry a tool and walk; they also walk along the top edge of other app windows.
- Idle sessions stay put.
- Sessions that need you show a badge above the head (`!` `?` `✋`) and hop periodically.
- Characters keep their distance and never overlap.
- Drag a character to move it. Double-click to bring the app running that session (Claude app or Terminal) to the front.
- When the mouse moves fast or you keep typing for about 3 seconds, the characters fade out; after 8 quiet seconds they creep back out (**Settings ▸ Hide while I'm busy, creep back out when I rest**, on by default). They do not pop back in place: each one starts just outside the nearest screen edge (left, right or bottom), pokes half its body out, waits a moment, then sneaks to where it was a few steps at a time, one after another. Whipping, gathering or dragging one ends the sneaking at once. They stay while the pointer is over a character or while in the carrot field. Only the time of the last key press is checked, never its content, and no permission is needed.

Turn on **Roam small** to show small characters without name tags.

### 4.3 Carrot field

**Plant in the carrot field** opens a field window at one side of the screen. All characters walk in and take their own seats. Drag the window to move it; press **Pull out** to release. In the field, characters are always shown small.

Field rules

| Item | Rule |
|---|---|
| Carrots | Always 10 (5 × 2 rows). One carrot = 10% of the 5-hour quota |
| Remaining carrots | ⌈10 × remaining quota ratio⌉. Example: 75% used → 3 carrots |
| Pulled from | The right end |
| Seating | Characters sit one per carrot from the left. The 11th onward sit on a third row without carrots |
| Starving | A character whose carrot is gone shows 🥕✕; the header reads "n starving" |
| Eating | When the usage check (every 5 minutes) removes a carrot, the character at that seat hops and a sound plays |
| Strike | At 0 carrots (quota exhausted) every Claude character goes on strike (see 5.4) |

If **Show remaining quota** (Settings) is off, all 10 carrots are shown as decoration.

## 5. Status display

### 5.1 Current activity

Claude Code sessions show their current activity, derived from the conversation log.

| Display | Meaning | Tool held |
|---|---|---|
| Reading · file | Reading a file | Book |
| Editing · file | Editing or writing a file | Pencil |
| Running · description | Shell command | Hammer |
| Searching · pattern | Search | Magnifier |
| Delegating | Running a sub-agent | Whip |
| Web searching / Reading the web | Web search or fetch | Globe |
| Thinking | Model reasoning | Thought bubble |
| Answering | Writing a reply | Speech bubble |

### 5.2 Waiting state

Idle sessions show why they stopped and for how long. States that need your input are highlighted in yellow.

| Display | Meaning |
|---|---|
| Your turn | Finished answering, waiting for your input |
| Asked you | Waiting for an answer or plan approval |
| Needs permission | Waiting for permission to run a tool |
| Resting | Idle |

### 5.3 Overload

When a session uses more than 1.5 CPU cores or more than 2 GB (or 10% of total) memory, its row and bars turn red and steam appears above the character. The header counts overloaded sessions.

When overload lasts, Whiplash can also speak up. **Settings ▸ When an agent is overloaded** has three modes and a threshold:

| Mode | What happens |
|---|---|
| Do nothing (default) | The critter turns red and steams, nothing else |
| Alert and ask me what to do | After the threshold a small panel appears at the top right with the agent's name, CPU, memory and how long it has been overloaded, and three buttons: **Stop it (Ctrl-C)**, **Go to the agent**, **Leave it**. It waits for you |
| Alert, then stop it automatically after 20 s | The same panel with a countdown. If you press nothing for 20 seconds, Whiplash sends Ctrl-C (direct-download edition only) |

The threshold is 1, 3, 5 or 10 minutes of continuous overload (default 3). "Leave it" and "Stop it" both silence that agent until it has cooled down for 20 seconds; if it overloads again later you are asked again. Stopping is the same as pressing Ctrl-C in its terminal: the current step is interrupted and the session stays open. Sessions inside the Claude desktop app, and everything in the App Store edition, cannot be stopped from here; the panel then only offers the other two buttons. A long build or test run is a normal reason to be overloaded, so the automatic mode is best kept for nights and unattended runs.

### 5.4 Remaining quota (🥕 carrots)

Turn on **Settings ▸ Show remaining quota** to display the remaining quota of your Claude subscription split into session (5-hour), weekly (all models) and per-model weekly (such as Fable) windows. The session window is drawn as ten carrots, the others as bars. Carrots disappear as the quota fills up; when it is exhausted the characters go on strike.

The lookup uses the token Claude Code stores in the Keychain when you log in. The first time, macOS shows a prompt asking for your **"login" Keychain password**. This is not a Claude login; it authorizes Whiplash to read the Keychain item, and the password is normally the same as your Mac login password. Choose **Always Allow** and it will not ask again.

| Situation | What to do |
|---|---|
| Password not accepted | The login Keychain password differs from your Mac password (it happens after a password change). Fix it in Keychain Access → login → Change Password, or click **Deny**; only the carrot field is then unavailable. |
| Asked every time | A changed signature triggers a new prompt. `build.sh` signs with an Apple Development certificate when one is in your Keychain, so the signature stays the same across builds. If you deny, the app stops asking for that run; toggle **Show remaining quota** off and on to retry. |
| "No Claude Code login" | Run `/login` in Claude Code first. |

If `~/.claude/.credentials.json` exists it is used instead of the Keychain and no prompt appears. The token is used only for the request and never stored. This feature is available in the direct-download edition only.

## 6. Controlling sessions

### 6.1 Send an instruction

Click a character or session row in place (without dragging) to open an input field. Type an instruction and press ⏎ to deliver it to that Claude Code session as a user message. Press esc to close.

- Idle sessions act on it immediately.
- Busy sessions read it after the current turn.
- On success the character flashes green and a sound plays.

One or two lines of context for that session appear above the field.

| Display | Meaning |
|---|---|
| ❓ question + option buttons | The session is waiting on a question (AskUserQuestion) or plan approval. A button sends that option as the reply. |
| 💬 last words | The tail of the session's last message (usually "…shall I?"). For idle sessions, quick replies **Yes, do it / Don't / Keep going** are shown. |

Options and last words are read from the transcript and cleared when a new instruction is sent.

### 6.2 Whip

Tells an idle or busy session to keep working.

**How**
1. Hover over the character for about 0.25 s. The character highlights and a whip appears next to the pointer.
2. Swipe the pointer across the character and back within 0.8 seconds, sideways or up and down. It has to be a real back-and-forth on the same line: passing over once, even diagonally, does nothing. For a lined-up row, up-and-down is easiest.

Alternatively press ⌃⌥W (random idle session) or right-click → **Whip — pick a task**.

**Trackpad**
- Each hit triggers trackpad haptic feedback (repeated for several critters).
- Two-finger flick: hover a critter and flick sideways to whip it. A long flick (about 260 px or more) whips every critter in the same row. Mouse wheels do not count.

**Several at once**
- Press ⌃⌥G (Come here) to line the critters up, then swing the pointer once across the row quickly (about 700 px/s or faster). Every critter you pass is whipped at the same time, and the sounds are layered per critter.
- ⌃⌥⇧W or the menu item **Whip everyone idle** sends the whip message to every idle session. Immune sessions are skipped. Sessions that are working or waiting for a permission are skipped too, so a busy session does not pile up "keep going" messages. Everyone reacts at once, but the messages go out one session at a time, 3 seconds apart, so a dozen agents do not all start a turn in the same instant and bog the Mac down. The same pacing applies when you sweep the mouse over several critters. In a multi-whip at most one helper agent is launched.

**What happens**
- Claude Code sessions receive a short message (default: `Whack! (Whiplash) Keep going with what you were doing. If you're done, pick the next thing and do it.`). Change it under **Auto-whip → Edit whip prompt…**.
- Agents that cannot receive messages (Codex, Gemini) or a picked task: a helper agent starts in the same project folder in read-only mode and works on the task. Results appear at the bottom of the window; click to open.

**Reaction**
- The character reacts with a sound. Repeated whips within 8 seconds escalate the reaction.
- Whipping a session that is waiting for you twice within 8 seconds sends nothing and shows a refusal instead.

**Avoiding accidents**
- A pointer that merely passes over the character does nothing.
- Enable **Whip only while holding ⌥** to require the ⌥ key.
- Right-click → **Whip immunity** excludes a session from manual and automatic whips; a 🛡 appears in its status line.

### 6.3 Auto-whip

Delivers the whip message to idle Claude Code sessions at a fixed interval until a chosen time.

- Menu bar icon → **Auto-whip** → choose a period (1 hour, 3 hours, until 6 PM, midnight, 9 AM).
- Interval: 3–60 minutes (default 10).
- Sessions waiting for permission, sessions idle for under a minute, and immune sessions are skipped.
- While active, the window header shows the end time; a sound plays when it ends.
- Survives relaunch until the end time.

> Auto-whip keeps agents consuming tokens for the chosen period. Start with a short period and a long interval, and keep your file-edit and command permissions as usual.

### 6.4 Other controls (right-click menu)

| Item | Action |
|---|---|
| Go to the agent | Jump to where that session lives: inside the Claude desktop app it opens that exact session; in Terminal or iTerm it selects that tab (direct-download edition; macOS asks once to let Whiplash control the terminal); otherwise it brings the hosting app to the front |
| Open folder | Reveal the project folder in Finder |
| Copy last prompt | Copy the last user prompt to the clipboard |
| Open transcript file | Open the session log (JSONL) |
| Stop current work (Ctrl-C) | Interrupt a Terminal session (not available for Claude app sessions) |
| Whip immunity | Exclude from whips |

### 6.5 Treats (praise) and the megaphone

A **treat** is the opposite of a whip. It delivers a praise prompt to the session (default: `🥕 Nice work! (Whiplash) Keep going just like this.`, editable under Settings ▸ Edit treat prompt…) and the critter hops with a "Yum!". Agents that cannot receive messages still react.

| Method | Action |
|---|---|
| Petting | Hover over a critter, then stroke **slowly** (30–180 px/s) side to side three times. Fast means whip, slow means treat |
| Right-click → 🥕 Give a treat | Treat that session |
| ⌃⌥T / menu **Treat everyone working** | Treat every working session |

The **megaphone** (⌃⌥B / menu **Megaphone — same message to everyone…**) opens the prompt box in broadcast mode: the text is delivered to every Claude session. Idle sessions read it immediately, busy ones after their turn.

### 6.6 Whip with your body

Turn these on under **Settings ▸ Whip with your body**. They are all off by default. Sensors, camera, microphone and network are used only while the matching switch is on, and nothing is recorded or stored. Each trigger whips **every idle session at once** (the same as ⌃⌥⇧W): the critters jump, the crack plays as a chorus, and in the full edition the whip prompt is delivered to each session. While a trigger is on, the menu shows its state on the line below it ("Listening…", "Camera access denied", and so on).

| Trigger | Gesture | Requirements |
|---|---|---|
| AirPods head flick | Wearing AirPods, turn your head quickly (over 5.5 rad/s) | macOS 14 or later; AirPods with motion sensors (Pro, 3rd gen, Max, Beats Fit Pro) |
| Camera hand swing | Swing a hand sideways across 30% of the frame within 0.35 s | Camera permission; tracks hand joints at 15 fps |
| Say "whoosh-crack!" | A short burst that jumps from quiet to loud within 50 ms | Microphone permission; only the level is measured |
| iPhone / iPad / Apple Watch remote | Flick the phone, snap your wrist with the Watch, or tap the button in the Whiplash Remote app on the same Wi‑Fi | Local network permission; see `WhiplashRemote/` |

**AirPods head flick.** The Mac reads the head-motion sensor in the AirPods (the same one Spatial Audio uses). A quick sideways snap of the head is about 6–10 rad/s; nodding along to music is around 2, so it does not trigger. There is a 1.5 s cooldown. If the AirPods are connected to another device at that moment, the Mac cannot read them and the status line says so. On macOS 13 the switch is hidden.

**Camera hand swing.** The camera opens only while the switch is on (the green light stays on the whole time). Vision tracks one hand's wrist; if it crosses 30% of the frame width in 0.35 s, that is a swing. Frames are analysed in memory and thrown away. Cooldown 2 s. Works best with the hand in front of the camera at arm's length.

**Say "whoosh-crack!".** The microphone level is sampled continuously; a crack is a jump from under −34 dBFS to over −14 dBFS within 50 ms, so normal speech, which ramps up slowly, does not trigger. Only the level is measured, never the audio itself. Cooldown 1.5 s.

**iPhone / iPad / Apple Watch remote.** This is a separate app, Whiplash Remote, in the `WhiplashRemote/` folder. Setting it up:

1. On the Mac, turn on **Settings ▸ Whip with your body ▸ Accept iPhone / iPad / Apple Watch remote** and allow "local network" when macOS asks. Whiplash then advertises itself as `_whiplash._udp` on the Wi‑Fi.
2. Install Whiplash Remote on the iPhone (the Watch app installs with it). It is not on the App Store yet; build it from `WhiplashRemote/` with Xcode (see its README).
3. Open the app on the phone with the phone on the same Wi‑Fi as the Mac. It lists every Mac running Whiplash and sends to all of them.
4. Flick the phone like a whip, snap the wrist wearing the Watch, or tap the big button. The phone plays the crack by itself the moment it detects the flick, before the Mac answers, so the feedback is instant. The Mac then reports what it did ("Whack! 3 whipped" or "Nobody to whip") under the button.
5. The phone also lists every session on the Mac with its state (working, resting, waiting for you, on strike) and a whip and a treat button per row, plus "Treat all", so you can pick one critter instead of whipping everyone.

A flick is a user-acceleration peak over 2.0 g followed by the hand stopping within 250 ms; walking is about 0.3 g and a shake about 1.5 g, so neither triggers it. The Watch relays through the phone with WatchConnectivity, so the phone has to be nearby and awake. The protocol is four plain-text UDP lines on port 47777, so anything on the Wi‑Fi can be a remote: a Shortcut, a Stream Deck, another Mac.

**Tuning and known limits.** The thresholds above were chosen from sensor documentation and typical values, not from a large test group, so they may need adjusting for your head, hand or wrist. They are single constants: `Motion.swift` (head flick), `HandCam.swift` (hand swing), `MouthWhip.swift` (mouth) and `WhiplashRemote/Shared/Flick.swift` (phone and Watch). In the App Store edition the body triggers bring the sessions' windows to the front and play the reaction; the whip prompt itself is delivered only by the direct-download edition (see 2.2).

### 6.7 Launching Claude

When Claude is not running, a **Claude (off)** character appears. Whip it to open the Claude app, or right-click → **Open claude in Terminal** and choose a recent project folder to start Claude Code there.

## 7. Menus and hotkeys

### 7.1 Menu bar icon / Dock menu

The menu bar icon and the Dock icon (right-click) show the same menu. Frequently used items are at the top level; everything else is under **Settings ▸**.

| Item | Action |
|---|---|
| Let loose — roam the screen / Show as window / Hide all | View switch. One of the three is checked (⌃⌥A / ⌃⌥H) |
| Come here | Gather all characters at the pointer (⌃⌥G) |
| Plant in the carrot field | Toggle the carrot field (⌃⌥C) |
| Whip any idle one | Whip one idle session (⌃⌥W) |
| Auto-whip ▸ | Period, interval and words |
| Settings ▸ | See below |
| Quit Whiplash | Quit |

**Settings ▸** items

| Item | Action |
|---|---|
| Roam small (no name tags) | Small characters without name tags (⌃⌥M) |
| Water tile behind critters | Background tile for roaming characters |
| Show list while roaming | Keep the list window during roaming (⌃⌥P) |
| Hide while I'm busy, creep back out when I rest | Hide characters during fast mouse movement or typing; when you stop, they sneak back in from the screen edge |
| Compact view / Always on top | Window settings |
| Whip only while holding ⌥ | Accident prevention |
| Show remaining quota — remaining quota | Enable quota lookup (a macOS Keychain prompt appears the first time, see 5.4) |
| Edit whip prompt… | The text delivered on a whip |
| Helper agent tasks ▸ | Task list for agents that cannot receive messages (Codex, Gemini), results folder |
| Theme ▸ / Language ▸ | Appearance and language |
| Edit hotkeys… | Opens `hotkeys.json`; reloaded automatically after saving |
| Show icon in Dock / Open at login | App settings |

### 7.2 Global hotkeys

Work regardless of the active app. No Accessibility permission needed.

| Hotkey | Action |
|---|---|
| ⌃⌥H | Hide / show all |
| ⌃⌥A | Roam / window |
| ⌃⌥M | Small / large |
| ⌃⌥C | Pen / let out |
| ⌃⌥G | Come here |
| ⌃⌥W | Whip an idle session |
| ⌃⌥⇧W | Whip every idle session |
| ⌃⌥T | Treat every working session |
| ⌃⌥B | Megaphone — same message to everyone |
| ⌃⌥P | Show list while roaming |

To change them, choose **Settings ▸ Edit hotkeys…**, edit `hotkeys.json` using the form `"ctrl+alt+h"` and save. The file is reloaded the next time the menu opens. Modifiers: ctrl, alt (option), cmd, shift. An empty value disables that hotkey.

## 8. Configuration files

All configuration lives in `~/Library/Application Support/Whiplash/`.

| File | Content |
|---|---|
| `whip-words.txt` | Message delivered on whip |
| `whips.json` | Helper agent tasks (`title`, `prompt`) |
| `hotkeys.json` | Global hotkeys |
| `whips/` | Helper agent results (.md) and logs |

Window positions, view mode, language and the immunity list are stored in the app's preferences (`com.kade.whiplash`).

## 9. Privacy and security

- Whiplash makes no network connections and sends no data anywhere.
- The process list is read from the operating system, read-only.
- Claude Code session details come from `~/.claude/sessions` and the tail of the transcript files under `~/.claude/projects`, read-only. Transcripts are re-read only when their size changes.
- Messages to sessions use the local socket and per-session token (`~/.claude/sessions/*.key`) that Claude Code provides. The token is read, never stored or logged.
- Helper agents run in read-only mode with file-editing and command tools disabled, and are stopped after 15 minutes.

## 10. Troubleshooting

| Symptom | Check |
|---|---|
| Menu bar icon not visible | On Macs with a notch, a full menu bar hides items. ⌘-drag another app's icon out, or use the Dock icon. |
| No session titles | Check your Claude Code version. The App Store edition needs home folder access (menu → Allow home folder access…). |
| Whip does not trigger | Hover briefly, then swipe across the character twice. Busy sessions only react; the message is read after the turn. Check whether ⌥-only mode is on. |
| Cannot send a message | Read the error under the input field. Not available in the App Store edition. |
| Characters cover my windows | Use Roam small, the pen, or the window view. |
| Hotkey conflicts | Change the combination under Edit hotkeys…. |
| Settings not applied (developers) | Once a sandboxed build has run, the `defaults` command targets the container. Use the explicit path `~/Library/Preferences/com.kade.whiplash.plist`. |

## 11. Uninstall

1. Quit via the menu bar icon → **Quit Whiplash**.
2. Move `/Applications/Whiplash.app` to the Trash.
3. To remove settings as well, delete `~/Library/Application Support/Whiplash/` and `~/Library/Preferences/com.kade.whiplash.plist`.
