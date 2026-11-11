# Whiplash for Windows and Linux

The cross-platform edition of Whiplash: the same pixel critters, session detection and whip for Claude Code on
Windows 10/11 and Linux. The macOS app stays the native Swift one in `../Sources` (shipped through the Mac App Store);
this folder is a separate app that reuses its sprites, sounds, icon and translation table.

```bash
cd desktop
npm install
npm start            # runs against your live ~/.claude sessions
npm test             # session parsing, socket protocol, whip gesture
npm run dist:linux   # dist/Whiplash-1.0.0-linux-x64.AppImage + .tar.gz
npm run dist:win     # dist/Whiplash-1.0.0-win-x64.zip   (dist:win:msi for the installer)
```

Releases: push a tag `v*` and `.github/workflows/release.yml` builds both platforms and attaches the files to a
GitHub Release. The repository must be public for other people to download them.

## Why Electron, not Tauri

Both were evaluated against the requirements (borderless transparent always-on-top windows, tray menu, global hotkeys,
sound, a zip/AppImage that runs without installing).

| | Electron | Tauri 2 |
|---|---|---|
| Transparent + always-on-top + click-through overlay | Mature on Windows and X11; `setIgnoreMouseEvents(…, {forward})` | Supported, but transparency on Linux depends on webkit2gtk and the compositor and is a known weak spot |
| Talking to Claude Code's messaging socket | `net.connect(path)` speaks to both a Unix socket and a Windows named pipe with one call | Needs separate Rust code paths (`UnixStream` vs `named_pipe`) |
| Tray, global shortcuts, screen geometry | Built in | Plugins (`tauri-plugin-global-shortcut`, tray in core) |
| Toolchain | Node only | Node + Rust (+ webkit2gtk headers on Linux, WebView2 on Windows) |
| Download size | ~100 MB zip / ~110 MB AppImage | ~10 MB (but relies on the system WebView) |
| Idle memory | ~150–250 MB across processes | ~40–80 MB |

Electron won on the three things this app actually does all day: drawing on a transparent overlay above every other
window, polling the cursor for the whip gesture, and writing two JSON lines to a local socket or named pipe. The price is
the bundle size, which the task preferred to keep small; it is the trade-off we accepted. If a Tauri port ever becomes
worth it, `src/main/sessions.js` (file parsing) and `src/main/swing.js` (gesture) are plain Node modules with tests and
would port one-to-one.

## How the whip reaches Claude Code on each platform

Claude Code writes a session file `~/.claude/sessions/<pid>.json` while it runs. Its `messagingSocketPath` is where
the session listens for messages, and `~/.claude/sessions/<pid>.<sha256 of that path>.key` holds the `peerToken`:

| Platform | `messagingSocketPath` |
|---|---|
| macOS | Unix socket, `/tmp/cc-socks/<pid>.sock` |
| Linux | Unix socket, `/tmp/cc-socks/<pid>.sock`, `/tmp/cc-socks-<uid>/<pid>.sock` or `/run/user/<uid>/cc-socks/<pid>.sock` |
| Windows | Named pipe, `\\.\pipe\cc-msg-<32 hex>` |

The app connects, writes `{"type":"auth","token":…}` and `{"type":"user","message":{"role":"user","content":…}}`,
and reads the one-line reply (see `src/main/messenger.js`; this is the same protocol the Mac app uses). The token is
read for that one request and never stored or logged. So on Windows and Linux the whip really delivers the prompt to the
session, exactly as on macOS. Agents without a messaging socket (Codex, Gemini CLI, Cursor) get "bring the window to
the front" and the reaction only.

**WSL.** Claude Code running inside WSL keeps its files in the WSL home and listens on a Linux socket, which the Windows
build cannot reach. Run the Linux build inside WSL (WSLg) instead, or point the Windows build at the WSL home with
`WHIPLASH_CLAUDE_DIR=\\wsl$\<distro>\home\<user>\.claude` to at least see the sessions (whipping will fall back to
bring-to-front).

## What is ported

| Feature | Windows / Linux |
|---|---|
| Claude Code session detection: title, busy / idle, your turn (`!` `?` `✋`), current tool, cost, lines | Yes (`src/main/sessions.js`, a port of `Sessions.swift`) |
| Agent process list with CPU and memory (Claude Code, Codex, Cursor, Gemini CLI, Antigravity, others) | Yes: `/proc` on Linux, one long-lived PowerShell `Get-CimInstance Win32_Process` on Windows |
| Roaming critters (transparent overlay), small / large, name tags, drag, double-click to bring to front | Yes |
| List window: critters in rows of N (5 / 8 / 10 / 15 / 20), CPU and memory bars | Yes |
| Whip gesture: hover 0.25 s, then two fast passes (≥ 400 px/s) within 0.8 s; sweep across a row | Yes (`src/main/swing.js`, polled from the global cursor at 40 Hz) |
| Treats (three slow strokes), megaphone, whip everyone idle, treat everyone working | Yes |
| Talk-back when you whip a critter that is waiting for you; immunity; strike on 429 | Yes |
| Sounds (`whip1-3.wav`, `angry.wav` from the Mac app) | Yes |
| Tray menu, global hotkeys (`hotkeys.json`, same format as the Mac app) | Yes |
| Send an instruction (click a critter, type, Enter) with quick-reply chips | Yes |
| Open at login | Yes (registry / `~/.config/autostart`) |
| Carrot field, remaining quota, Claude ghost launcher, auto-whip timer | Not yet (quota needs the Keychain token; the rest is scheduled after the first release) |
| Whip with your body (AirPods, camera, microphone), iPhone / Watch remote | No (macOS only) |
| Hide while you type | No (would need a global keyboard hook) |

## Platform notes

- **Windows.** The overlay is click-through except over a critter. The tray icon lives in the notification area
  (show hidden icons if you do not see it). Global hotkeys use Ctrl+Alt by default. SmartScreen will warn about the
  unsigned zip the first time; choose *More info → Run anyway*. The MSI is optional and unsigned too.
- **Linux.** Needs a compositing window manager for transparency (GNOME, KDE, Sway via XWayland all work).
  Under Wayland, Electron runs through XWayland by default; global hotkeys and *always on top* are not available on pure
  Wayland sessions. The tray needs an AppIndicator-capable panel (GNOME: the AppIndicator extension). `Bring window to
  front` uses `xdotool` or `wmctrl` when installed. AppImage needs `libfuse2` on some distributions, or run the
  `tar.gz` directly (`./whiplash`).
- **Process scan cost.** Linux reads `/proc` every 2 s (a few ms). Windows asks PowerShell every 3 s (100–300 ms of
  PowerShell CPU, in a single reused process).
- **Only the primary display** gets the overlay for now.

## Files

| Where | What |
|---|---|
| `src/main/main.js` | Windows, tray, menus, IPC, cursor loop |
| `src/main/model.js` | State: whip / treat / megaphone / anger / immunity (port of `Model.swift`) |
| `src/main/sessions.js` | `~/.claude` session + transcript tail reader (port of `Sessions.swift`) |
| `src/main/messenger.js` | Socket / named-pipe delivery (port of `Messenger.swift`) |
| `src/main/processes.js`, `proc-linux.js`, `proc-win.js`, `proc-darwin.js` | Process grouping (port of `Monitor.swift`); darwin is dev-only |
| `src/main/swing.js` | Whip gesture detector (port of `trackSwing` in `App.swift`) |
| `src/renderer/overlay.*`, `list.*`, `draw.js`, `sound.js` | Pages |
| `src/shared/sprites.json`, `lang.json` | Generated from `../Sources/Sprites.swift` and `../Sources/Lang.swift` by `tools/extract-*.js` |
| `tools/prepare-assets.js` | Copies `../Resources/*.wav` and `../AppIcon.iconset` into `assets/` before every run / build |

Config lives in `%APPDATA%\Whiplash` (Windows) or `~/.config/whiplash` (Linux): `settings.json`, `whip-words.txt`,
`treat-words.txt`, `hotkeys.json`. Environment switches for development: `WHIPLASH_DEMO=1` (fake sessions),
`WHIPLASH_DRY_WHIP=1` (whips make sound only), `WHIPLASH_SNAPSHOT=<dir>` (+ `WHIPLASH_SNAPSHOT_QUIT=1`) saves PNGs of both
windows after 5 s, `WHIPLASH_DEBUG=1` prints renderer console output, `WHIPLASH_CLAUDE_DIR`, `WHIPLASH_CONFIG_DIR`.

Version and bundle id match the Mac app: 1.0, `com.kade.whiplash`.
