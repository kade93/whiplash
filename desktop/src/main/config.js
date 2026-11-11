// Settings and the editable text files, all under the per-user config folder (see paths.configDir):
//   settings.json     view mode, critters per row, language, immune sessions, always on top …
//   whip-words.txt    the message a whip delivers
//   treat-words.txt   the message a treat delivers
//   hotkeys.json      global hotkeys ("ctrl+alt+h")
const fs = require('fs');
const path = require('path');
const paths = require('./paths');
const { t } = require('../shared/lang');

const dir = paths.ensureDir(paths.configDir());
const files = {
  settings: path.join(dir, 'settings.json'),
  whipWords: path.join(dir, 'whip-words.txt'),
  treatWords: path.join(dir, 'treat-words.txt'),
  hotkeys: path.join(dir, 'hotkeys.json'),
};

const DEFAULTS = {
  lang: 'en',            // en | ko | ja
  roaming: true,         // critters walk the screen (false = list window)
  critterSmall: true,    // roam small: no name tags
  compactPerRow: 10,     // list window: critters per row before wrapping
  alwaysOnTop: true,
  hidden: false,
  needsOption: false,    // whip only while holding Alt
  critterBox: false,     // water-colored box behind roaming critters
  immune: [],            // sessionIds that are never whipped
  panelBounds: null,     // list window position
};

let settings = { ...DEFAULTS };
try { settings = { ...DEFAULTS, ...JSON.parse(fs.readFileSync(files.settings, 'utf8')) }; } catch {}

function get(k) { return settings[k]; }
function set(k, v) {
  settings[k] = v;
  try { fs.writeFileSync(files.settings, JSON.stringify(settings, null, 2) + '\n'); } catch {}
}
function all() { return { ...settings }; }

function whipWordsDefault() { return t("Whack! (Whiplash) Keep going with what you were doing. If you're done, pick the next thing and do it."); }
function treatWordsDefault() { return t('🥕 Nice work! (Whiplash) Keep going just like this.'); }

function loadText(file, fallback) {
  try {
    const s = fs.readFileSync(file, 'utf8').trim();
    if (s) return s;
  } catch {}
  try { if (!fs.existsSync(file)) fs.writeFileSync(file, fallback + '\n'); } catch {}
  return fallback;
}
function whipWords() { return loadText(files.whipWords, whipWordsDefault()); }
function treatWords() { return loadText(files.treatWords, treatWordsDefault()); }

const HOTKEY_DEFAULTS = {
  hide: 'ctrl+alt+h', roam: 'ctrl+alt+a', small: 'ctrl+alt+m', whip: 'ctrl+alt+w', whipAll: 'ctrl+alt+shift+w',
  treatAll: 'ctrl+alt+t', megaphone: 'ctrl+alt+b', gather: 'ctrl+alt+g', panel: 'ctrl+alt+p',
};
function hotkeys() {
  let combos = { ...HOTKEY_DEFAULTS };
  try { combos = { ...combos, ...JSON.parse(fs.readFileSync(files.hotkeys, 'utf8')) }; }
  catch { try { fs.writeFileSync(files.hotkeys, JSON.stringify(HOTKEY_DEFAULTS, null, 2) + '\n'); } catch {} }
  return combos;
}

module.exports = { dir, files, DEFAULTS, HOTKEY_DEFAULTS, get, set, all, whipWords, treatWords, hotkeys };
