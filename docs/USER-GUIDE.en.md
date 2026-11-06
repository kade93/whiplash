# Whiplash User Guide

Version 0.2 · macOS 13 or later · Apple Silicon / Intel

Whiplash is a desktop utility that monitors and controls AI coding agents running on your Mac (Claude Code, Codex, Cursor, Gemini CLI and others). Each agent session is shown as a character on screen, so you can see at a glance what it is doing, whether it is waiting for you, and how much CPU and memory it uses. You can also send instructions to a session or nudge it back to work.

---

## 1. System requirements

| Item | Requirement |
|---|---|
| Operating system | macOS 13 Ventura or later |
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
| Traffic lights | Red: close / Yellow: compact view / Green: roaming |
| Header | Session count, working, waiting for you, overloaded, auto-whip end time |
| CPU / Memory bars | Color = agents, gray = other apps, empty = free |
| Session row | Character, session title, project folder, running cost, changed lines, current activity, CPU and memory |
| Footer | Agent data folder sizes, free disk space, Whiplash's own usage |

Double-click the window to switch to **Compact view** (characters and bars only).

### 4.2 Roaming

Each session becomes a character in its own transparent window and walks around the screen.

- Working sessions carry a tool and walk; they also walk along the top edge of other app windows.
- Idle sessions stay put.
- Sessions that need you show a badge above the head (`!` `?` `✋`) and hop periodically.
- Characters keep their distance and never overlap.
- Drag a character to move it. Double-click to bring the app running that session (Claude app or Terminal) to the front.
- When the mouse moves fast or you keep typing for about 3 seconds, the characters fade out; after 8 quiet seconds they return (**Settings ▸ Hide while I'm busy**, on by default). They stay while the pointer is over a character or while in the carrot field. Only the time of the last key press is checked, never its content, and no permission is needed.

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
2. Swipe the pointer across the character twice within 0.8 seconds, sideways or up and down. For a lined-up row, up-and-down is easiest.

Alternatively press ⌃⌥W (random idle session) or right-click → **Whip — pick a task**.

**Trackpad**
- Each hit triggers trackpad haptic feedback (repeated for several critters).
- Two-finger flick: hover a critter and flick sideways to whip it. A long flick (about 260 px or more) whips every critter in the same row. Mouse wheels do not count.

**Several at once**
- Press ⌃⌥G (Come here) to line the critters up, then swing the pointer once across the row quickly (about 700 px/s or faster). Every critter you pass is whipped at the same time, and the sounds are layered per critter.
- ⌃⌥⇧W or the menu item **Whip everyone idle** sends the whip message to every idle session. Immune sessions are skipped.

**What happens**
- Claude Code sessions receive a short message (default: `Whack! (Whiplash) Keep going with what you were doing. If you're done, pick the next thing and do it.`). Change it under **Auto-whip → Edit whip words…**.
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
| Bring window to front | Activate the app running the session |
| Open folder | Reveal the project folder in Finder |
| Copy last prompt | Copy the last user prompt to the clipboard |
| Open transcript file | Open the session log (JSONL) |
| Stop current work (Ctrl-C) | Interrupt a Terminal session (not available for Claude app sessions) |
| Whip immunity | Exclude from whips |

### 6.5 Whip with your body

Turn these on under **Settings ▸ Whip with your body**. Sensors, camera, microphone and network are used only while on, and nothing is recorded. Each trigger whips every idle session (same as ⌃⌥⇧W).

| Trigger | Gesture | Requirements |
|---|---|---|
| AirPods head flick | Wearing AirPods, turn your head quickly (over 5.5 rad/s) | macOS 14 or later; AirPods with motion sensors (Pro, 3rd gen, Max, Beats Fit Pro) |
| Camera hand swing | Swing a hand sideways across 30% of the frame within 0.35 s | Camera permission; tracks hand joints at 15 fps |
| Say "whoosh-crack!" | A short burst that jumps from quiet to loud within 50 ms | Microphone permission; only the level is measured |
| iPhone / iPad / Apple Watch remote | Flick the phone, snap your wrist with the Watch, or tap the button in the Whiplash Remote app on the same Wi‑Fi | Local network permission; see `WhiplashRemote/` |

The menu shows each trigger's state (listening, permission denied, and so on).

### 6.6 Launching Claude

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
| Hide while I'm busy | Hide characters during fast mouse movement or typing; return when quiet |
| Compact view / Always on top | Window settings |
| Whip only while holding ⌥ | Accident prevention |
| Show remaining quota — remaining quota | Enable quota lookup (a macOS Keychain prompt appears the first time, see 5.4) |
| Whip tasks ▸ | Edit helper agent tasks, open results folder |
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

Window positions, view mode, language and the immunity list are stored in the app's preferences (`kr.urbanism.whiplash`).

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
| Settings not applied (developers) | Once a sandboxed build has run, the `defaults` command targets the container. Use the explicit path `~/Library/Preferences/kr.urbanism.whiplash.plist`. |

## 11. Uninstall

1. Quit via the menu bar icon → **Quit Whiplash**.
2. Move `/Applications/Whiplash.app` to the Trash.
3. To remove settings as well, delete `~/Library/Application Support/Whiplash/` and `~/Library/Preferences/kr.urbanism.whiplash.plist`.
