// Where things live. WHIPLASH_CLAUDE_DIR overrides ~/.claude (for example a WSL home seen from Windows).
const os = require('os');
const path = require('path');
const fs = require('fs');

const home = os.homedir();
const claudeDir = process.env.WHIPLASH_CLAUDE_DIR || path.join(home, '.claude');

/** Per-user config folder: %APPDATA%\Whiplash, ~/.config/whiplash, ~/Library/Application Support/Whiplash */
function configDir() {
  if (process.env.WHIPLASH_CONFIG_DIR) return process.env.WHIPLASH_CONFIG_DIR;
  if (process.platform === 'win32') return path.join(process.env.APPDATA || path.join(home, 'AppData', 'Roaming'), 'Whiplash');
  if (process.platform === 'darwin') return path.join(home, 'Library', 'Application Support', 'Whiplash');
  return path.join(process.env.XDG_CONFIG_HOME || path.join(home, '.config'), 'whiplash');
}

function ensureDir(d) { try { fs.mkdirSync(d, { recursive: true }); } catch {} return d; }

module.exports = {
  home, claudeDir,
  sessionsDir: path.join(claudeDir, 'sessions'),
  projectsDir: path.join(claudeDir, 'projects'),
  configDir, ensureDir,
};
