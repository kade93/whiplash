// Global hotkeys through Electron's globalShortcut. Config format is the same as the Mac app's hotkeys.json:
// "ctrl+alt+h" (modifiers: ctrl, alt/option, cmd/win/super, shift). Empty string = off.
const { globalShortcut } = require('electron');
const { t } = require('../shared/lang');

const TITLES = {
  hide: 'Hide / show all', roam: 'Roam / window', small: 'Small / large', whip: 'Whip any idle one',
  whipAll: 'Whip everyone idle', treatAll: 'Treat everyone working 🥕', megaphone: 'Megaphone — same message to everyone',
  gather: 'Come here (gather at cursor)', panel: 'Show list while roaming (both at once)',
};

/** "ctrl+alt+h" → "Control+Alt+H" (Electron accelerator), or null when it can't be read */
function toAccelerator(text) {
  if (!text || typeof text !== 'string') return null;
  const parts = text.toLowerCase().split('+').map(s => s.trim()).filter(Boolean);
  const key = parts.pop();
  if (!key) return null;
  const mods = [];
  for (const m of parts) {
    if (['ctrl', 'control', '^'].includes(m)) mods.push('Control');
    else if (['alt', 'option', 'opt', '⌥'].includes(m)) mods.push('Alt');
    else if (['cmd', 'command', '⌘', 'win', 'windows', 'super', 'meta'].includes(m)) mods.push('Super');
    else if (['shift', '⇧'].includes(m)) mods.push('Shift');
    else return null;
  }
  const named = { space: 'Space', enter: 'Return', return: 'Return', esc: 'Escape', escape: 'Escape', tab: 'Tab',
                  up: 'Up', down: 'Down', left: 'Left', right: 'Right', '`': '`', '-': '-', '=': '=', '[': '[', ']': ']' };
  const k = named[key] || (/^f\d{1,2}$/.test(key) ? key.toUpperCase() : key.length === 1 ? key.toUpperCase() : null);
  if (!k) return null;
  return [...mods, k].join('+');
}

/** "ctrl+alt+h" → "Ctrl+Alt+H" for menus */
function pretty(text) {
  const acc = toAccelerator(text);
  return acc ? acc.replace('Control', 'Ctrl') : '';
}

let registered = [];
function register(combos, actions) {
  for (const a of registered) globalShortcut.unregister(a);
  registered = [];
  const result = {};
  for (const [name, fn] of Object.entries(actions)) {
    const acc = toAccelerator(combos[name]);
    result[name] = '';
    if (!acc) continue;
    try { if (globalShortcut.register(acc, fn)) { registered.push(acc); result[name] = combos[name]; } } catch {}
  }
  return result;
}

function unregisterAll() { globalShortcut.unregisterAll(); registered = []; }

module.exports = { TITLES, toAccelerator, pretty, register, unregisterAll, title: k => t(TITLES[k] || k) };
