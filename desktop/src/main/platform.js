// Best-effort platform helpers: bring a session's window to the front, open claude in a terminal, login item.
const { execFile, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

function run(cmd, args, opts = {}) {
  return new Promise(resolve => execFile(cmd, args, { timeout: 4000, windowsHide: true, ...opts }, (err, out) => resolve(err ? null : String(out))));
}

/** Try to activate the window of any pid in the list (the session's process, then its parents). */
async function bringToFront(pids) {
  if (process.platform === 'win32') {
    for (const pid of pids) {
      const out = await run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `(New-Object -ComObject WScript.Shell).AppActivate(${pid})`]);
      if (out && out.trim() === 'True') return true;
    }
    return false;
  }
  if (process.platform === 'linux') {
    for (const pid of pids) {
      const ids = await run('xdotool', ['search', '--onlyvisible', '--pid', String(pid)]);
      const first = ids && ids.trim().split('\n')[0];
      if (first) { await run('xdotool', ['windowactivate', first]); return true; }
      const wm = await run('wmctrl', ['-lp']);
      const line = wm && wm.split('\n').find(l => l.split(/\s+/)[2] === String(pid));
      if (line) { await run('wmctrl', ['-ia', line.split(/\s+/)[0]]); return true; }
    }
    return false;
  }
  if (process.platform === 'darwin') {
    for (const pid of pids) {
      const r = await run('osascript', ['-e', `tell application "System Events" to set frontmost of (first process whose unix id is ${pid}) to true`]);
      if (r !== null) return true;
    }
  }
  return false;
}

/** Open a terminal running `claude` in dir */
function openClaudeTerminal(dir) {
  const cwd = dir && fs.existsSync(dir) ? dir : os.homedir();
  try {
    if (process.platform === 'win32') {
      spawn('cmd.exe', ['/c', 'start', '"Claude Code"', 'cmd', '/k', 'claude'], { cwd, detached: true, stdio: 'ignore', windowsHide: true }).unref();
    } else if (process.platform === 'darwin') {
      spawn('osascript', ['-e', `tell application "Terminal" to do script "cd ${JSON.stringify(cwd)} && claude"`, '-e', 'tell application "Terminal" to activate'], { detached: true, stdio: 'ignore' }).unref();
    } else {
      const terms = [['x-terminal-emulator', ['-e', 'claude']], ['gnome-terminal', ['--', 'claude']], ['konsole', ['-e', 'claude']], ['xfce4-terminal', ['-e', 'claude']], ['kitty', ['claude']], ['alacritty', ['-e', 'claude']], ['xterm', ['-e', 'claude']]];
      for (const [bin, args] of terms) {
        if (!which(bin)) continue;
        spawn(bin, args, { cwd, detached: true, stdio: 'ignore' }).unref();
        return true;
      }
      return false;
    }
    return true;
  } catch { return false; }
}

function which(bin) {
  for (const d of (process.env.PATH || '').split(path.delimiter)) { if (d && fs.existsSync(path.join(d, bin))) return path.join(d, bin); }
  return null;
}

/** Linux autostart via ~/.config/autostart; Windows/macOS use app.setLoginItemSettings (handled by the caller) */
function linuxAutostart(enable, exePath) {
  const dir = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'autostart');
  const file = path.join(dir, 'whiplash.desktop');
  try {
    if (!enable) { fs.rmSync(file, { force: true }); return; }
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(file, `[Desktop Entry]\nType=Application\nName=Whiplash\nExec=${exePath}\nX-GNOME-Autostart-enabled=true\n`);
  } catch {}
}
function linuxAutostartEnabled() {
  return fs.existsSync(path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'autostart', 'whiplash.desktop'));
}

module.exports = { bringToFront, openClaudeTerminal, linuxAutostart, linuxAutostartEnabled, which };
