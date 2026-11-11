// Whiplash for Windows and Linux — Electron main process.
// Windows: an overlay (transparent, frameless, always on top, click-through except over a critter) for roaming,
// and a small list window. The tray icon carries the menu; global hotkeys mirror the Mac app.
const { app, BrowserWindow, Tray, Menu, screen, ipcMain, shell, clipboard, nativeImage, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const config = require('./config');
const { Model, GHOST_ID } = require('./model');
const { SwingDetector } = require('./swing');
const hotkeys = require('./hotkeys');
const platform = require('./platform');
const lang = require('../shared/lang');
const { t, tf } = lang;

if (process.platform === 'linux') app.commandLine.appendSwitch('enable-transparent-visuals');
if (!app.requestSingleInstanceLock()) { app.quit(); }

const assets = path.join(__dirname, '..', '..', 'assets');
const model = new Model();
let overlay = null, list = null, tray = null;
let promptOpen = false, dragging = false, mouseInside = null;
let targetsFrom = { overlay: [], list: [] };
const swing = new SwingDetector({
  onSwing: id => model.whip(id),
  onPet: id => model.treat(id),
  onSweep: ids => model.whipMany(ids.filter(i => i !== '#prompt')),
  onHover: (id, p) => { send('hover', id === '#prompt' ? null : id, p); },
});

function debugConsole(w) {
  if (!process.env.WHIPLASH_DEBUG) return;
  w.webContents.on('console-message', (e, level, msg, line, src) => console.log(`[renderer ${path.basename(src || '')}:${line}]`, msg));
}
function send(channel, ...args) { for (const w of [overlay, list]) if (w && !w.isDestroyed()) w.webContents.send(channel, ...args); }
function settingsPayload() { return config.all(); }

// MARK: windows
function display() { return screen.getPrimaryDisplay(); }

function createOverlay() {
  const d = display();
  const b = d.workArea;
  overlay = new BrowserWindow({
    x: b.x, y: b.y, width: b.width, height: b.height,
    frame: false, transparent: true, alwaysOnTop: config.get('alwaysOnTop'), skipTaskbar: true, resizable: false, movable: false,
    hasShadow: false, focusable: true, show: false, type: process.platform === 'linux' ? 'dock' : undefined,
    webPreferences: { preload: path.join(__dirname, '..', 'renderer', 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: false, backgroundThrottling: false },
  });
  overlay.setMenu(null);
  debugConsole(overlay);
  overlay.setAlwaysOnTop(config.get('alwaysOnTop'), 'screen-saver');
  overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  overlay.setIgnoreMouseEvents(true, { forward: true });
  overlay.loadFile(path.join(__dirname, '..', 'renderer', 'overlay.html'));
  overlay.webContents.on('did-finish-load', () => {
    overlay.webContents.send('bounds', b);
    overlay.webContents.send('settings', settingsPayload());
    overlay.webContents.send('snapshot', model.snapshot);
  });
  overlay.on('closed', () => { overlay = null; });
}

function createList() {
  const saved = config.get('panelBounds');
  const d = display().workArea;
  list = new BrowserWindow({
    x: saved ? saved.x : d.x + d.width - 340, y: saved ? saved.y : d.y + 20, width: 320, height: 160,
    frame: false, transparent: true, alwaysOnTop: config.get('alwaysOnTop'), skipTaskbar: true, resizable: false, show: false, hasShadow: false,
    webPreferences: { preload: path.join(__dirname, '..', 'renderer', 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: false, backgroundThrottling: false },
  });
  list.setMenu(null);
  debugConsole(list);
  list.setAlwaysOnTop(config.get('alwaysOnTop'), 'floating');
  list.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  list.loadFile(path.join(__dirname, '..', 'renderer', 'list.html'));
  list.webContents.on('did-finish-load', () => {
    list.webContents.send('settings', settingsPayload());
    list.webContents.send('snapshot', model.snapshot);
    const p = list.getPosition(); list.webContents.send('bounds', { x: p[0], y: p[1] });
  });
  list.on('moved', () => { const p = list.getPosition(); config.set('panelBounds', { x: p[0], y: p[1] }); list.webContents.send('bounds', { x: p[0], y: p[1] }); });
  list.on('closed', () => { list = null; });
}

function applyVisibility() {
  const hidden = config.get('hidden');
  const roaming = config.get('roaming');
  if (!overlay || !list) return;
  if (hidden) { overlay.hide(); list.hide(); }
  else {
    if (roaming) overlay.showInactive(); else overlay.hide();
    if (!roaming || config.get('panelWithCritters')) list.showInactive(); else list.hide();
  }
  model.setVisible(!hidden);
  swing.setTargets(currentTargets());
  refreshTray();
}

function currentTargets() {
  const out = [];
  if (overlay && overlay.isVisible()) out.push(...targetsFrom.overlay);
  if (list && list.isVisible()) out.push(...targetsFrom.list);
  return out;
}

// MARK: cursor polling → whip gesture and click-through toggling
function startCursorLoop() {
  let lastIgnore = true;
  setInterval(() => {
    if (config.get('hidden')) return;
    const p = screen.getCursorScreenPoint();
    const now = Date.now() / 1000;
    swing.feed(p, now);
    if (overlay && overlay.isVisible()) {
      const over = swing.hit(p, 6);
      const want = !(over || promptOpen || dragging);
      if (want !== lastIgnore) {
        lastIgnore = want;
        overlay.setIgnoreMouseEvents(want, { forward: true });
      }
      if (over && over !== '#prompt') overlay.webContents.send('cursor', p);
    }
  }, 25);
}

// MARK: tray and menus
function trayIcon() {
  const file = process.platform === 'win32' ? 'tray-16.png' : 'tray.png';
  const img = nativeImage.createFromPath(path.join(assets, 'icon', file));
  return img.isEmpty() ? nativeImage.createEmpty() : img;
}

function statusLine() {
  const gs = model.snapshot.groups.filter(g => !g.ghost);
  if (!gs.length) return t('No agents running right now');
  return tf('%d critters · %d working · %d need you', gs.length, gs.filter(g => g.awake).length, gs.filter(g => g.needsYou).length);
}

function buildMenu() {
  const hk = config.hotkeys();
  const acc = k => hotkeys.pretty(hk[k]) || undefined;
  const sessions = model.snapshot.groups.filter(g => g.session && !g.ghost);
  const langItems = Object.entries(lang.LANGS).map(([id, title]) => ({ label: title, type: 'radio', checked: config.get('lang') === id, click: () => setLang(id) }));
  const perRow = [5, 8, 10, 15, 20].map(n => ({ label: String(n), type: 'radio', checked: config.get('compactPerRow') === n, click: () => { config.set('compactPerRow', n); send('settings', settingsPayload()); } }));
  return Menu.buildFromTemplate([
    { label: statusLine(), enabled: false },
    { type: 'separator' },
    { label: t('Hide all'), type: 'checkbox', checked: config.get('hidden'), accelerator: acc('hide'), click: () => toggle('hidden') },
    { label: t('Let loose — roam the screen'), type: 'checkbox', checked: config.get('roaming'), accelerator: acc('roam'), click: () => toggle('roaming') },
    { label: t('Roam small (no name tags)'), type: 'checkbox', checked: config.get('critterSmall'), accelerator: acc('small'), click: () => toggle('critterSmall') },
    { label: t('Show list while roaming (both at once)'), type: 'checkbox', checked: !!config.get('panelWithCritters'), accelerator: acc('panel'), click: () => toggle('panelWithCritters') },
    { label: t('Come here — gather at the cursor'), accelerator: acc('gather'), click: gather },
    { type: 'separator' },
    { label: t('Whip any idle one'), accelerator: acc('whip'), click: () => model.whipRandom() },
    { label: t('Whip everyone idle'), accelerator: acc('whipAll'), click: () => model.whipAll() },
    { label: t('Treat everyone working 🥕'), accelerator: acc('treatAll'), click: () => model.treatAll() },
    { label: t('Megaphone — same message to everyone…'), accelerator: acc('megaphone'), click: megaphone },
    { type: 'separator' },
    ...(sessions.length ? [{ label: t('Sessions'), submenu: sessions.map(g => ({ label: `${g.session.name || g.label} — ${g.awake ? t('Working') : g.needsYou ? t('Your turn') : t('Idle')}`, submenu: sessionMenu(g) })) }] : []),
    { label: t('Settings'), submenu: [
      { label: t('Critters per row'), submenu: perRow },
      { label: t('Always on top'), type: 'checkbox', checked: config.get('alwaysOnTop'), click: () => { toggle('alwaysOnTop'); for (const w of [overlay, list]) if (w) w.setAlwaysOnTop(config.get('alwaysOnTop'), w === overlay ? 'screen-saver' : 'floating'); } },
      { label: t('Water box behind critters'), type: 'checkbox', checked: config.get('critterBox'), click: () => toggle('critterBox') },
      { label: t('Whip only while holding ⌥'), type: 'checkbox', checked: config.get('needsOption'), click: () => { toggle('needsOption'); swing.needsOption = config.get('needsOption'); } },
      { label: t('Open at login'), type: 'checkbox', checked: loginEnabled(), click: m => setLogin(m.checked) },
      { type: 'separator' },
      { label: t('Language'), submenu: langItems },
      { type: 'separator' },
      { label: t('Edit whip prompt…'), click: () => { config.whipWords(); shell.openPath(config.files.whipWords); } },
      { label: t('Edit treat prompt…'), click: () => { config.treatWords(); shell.openPath(config.files.treatWords); } },
      { label: t('Edit hotkeys…'), click: () => { config.hotkeys(); shell.openPath(config.files.hotkeys); } },
      { label: t('Reload hotkeys'), click: registerHotkeys },
      { label: t('Open config folder'), click: () => shell.openPath(config.dir) },
    ] },
    { type: 'separator' },
    { label: t('Quit Whiplash'), click: () => app.quit() },
  ]);
}

function sessionMenu(g) {
  const s = g.session;
  const items = [];
  if (!g.ghost) {
    items.push({ label: t('Whip'), click: () => model.whip(g.id) });
    items.push({ label: t('🥕 Give a treat'), click: () => model.treat(g.id) });
    if (s) items.push({ label: t('Send an instruction…'), click: () => openPrompt(g.id) });
    items.push({ type: 'separator' });
    items.push({ label: t('Bring window to front'), click: () => bringToFront(g) });
    if (g.dir) items.push({ label: t('Open folder'), click: () => shell.openPath(g.dir) });
    if (s && s.lastPrompt) items.push({ label: t('Copy last prompt'), click: () => clipboard.writeText(s.lastPrompt) });
    if (s && s.transcript) items.push({ label: t('Open transcript file'), click: () => shell.openPath(s.transcript) });
    if (s) items.push({ type: 'separator' }, { label: t('Whip immunity'), type: 'checkbox', checked: g.immune, click: () => model.toggleImmune(g.id) });
  } else {
    items.push({ label: t('Open claude in Terminal'), submenu: [{ label: '~', click: () => platform.openClaudeTerminal(null) }, ...model.reader.recentProjects(8).map(d => ({ label: path.basename(d), click: () => platform.openClaudeTerminal(d) }))] });
  }
  return items;
}

function refreshTray() {
  if (!tray) return;
  tray.setContextMenu(buildMenu());
  tray.setToolTip('Whiplash — ' + statusLine());
}

function createTray() {
  tray = new Tray(trayIcon());
  tray.setToolTip('Whiplash');
  tray.on('click', () => { if (process.platform !== 'linux') tray.popUpContextMenu(buildMenu()); });
  refreshTray();
}

// MARK: actions
function toggle(key) { config.set(key, !config.get(key)); send('settings', settingsPayload()); applyVisibility(); }
function setLang(id) { config.set('lang', id); lang.setLang(id); send('settings', settingsPayload()); registerHotkeys(); refreshTray(); }
function gather() {
  if (!config.get('roaming')) return;
  const p = screen.getCursorScreenPoint();
  if (overlay) overlay.webContents.send('gather', p);
}
function openPrompt(id, broadcast = false) {
  if (!overlay) return;
  if (!config.get('roaming') || config.get('hidden')) { config.set('hidden', false); config.set('roaming', true); send('settings', settingsPayload()); applyVisibility(); }
  overlay.webContents.send('open-prompt', id, broadcast);
  overlay.setIgnoreMouseEvents(false);
  overlay.focus();
}
function megaphone() { openPrompt('broadcast:all', true); }
async function bringToFront(g) {
  const pids = [g.rootPID];
  const ok = await platform.bringToFront(pids);
  if (!ok) model.emit('sound', 'basso');
}
function loginEnabled() { return process.platform === 'linux' ? platform.linuxAutostartEnabled() : app.getLoginItemSettings().openAtLogin; }
function setLogin(on) { if (process.platform === 'linux') platform.linuxAutostart(on, process.env.APPIMAGE || process.execPath); else app.setLoginItemSettings({ openAtLogin: on }); }

function registerHotkeys() {
  const got = hotkeys.register(config.hotkeys(), {
    hide: () => toggle('hidden'), roam: () => toggle('roaming'), small: () => toggle('critterSmall'), panel: () => toggle('panelWithCritters'),
    whip: () => model.whipRandom(), whipAll: () => model.whipAll(), treatAll: () => model.treatAll(), megaphone, gather,
  });
  const missing = Object.entries(config.hotkeys()).filter(([k, v]) => v && !got[k]).map(([k]) => k);
  if (missing.length) console.warn('hotkeys not registered:', missing.join(', '));
}

// MARK: IPC
ipcMain.on('targets', (e, rects) => {
  const from = overlay && e.sender === overlay.webContents ? 'overlay' : 'list';
  targetsFrom[from] = rects;
  swing.setTargets(currentTargets());
});
ipcMain.on('prompt-open', (e, open) => { promptOpen = open; if (!open && overlay) overlay.setIgnoreMouseEvents(true, { forward: true }); });
ipcMain.on('drag', (e, on) => { dragging = on; });
ipcMain.on('context-menu', (e, id, at) => {
  const g = model.group(id);
  if (!g) return;
  const win = BrowserWindow.fromWebContents(e.sender);
  if (win === overlay) overlay.setIgnoreMouseEvents(false);
  const menu = Menu.buildFromTemplate([{ label: g.session ? (g.session.name || g.label) : g.label, enabled: false }, { type: 'separator' }, ...sessionMenu(g)]);
  menu.popup({ window: win, callback: () => { if (win === overlay && !promptOpen) overlay.setIgnoreMouseEvents(true, { forward: true }); } });
});
ipcMain.on('bring-to-front', (e, id) => { const g = model.group(id); if (g) bringToFront(g); });
ipcMain.on('whip', (e, id) => model.whip(id));
ipcMain.on('fit', (e, size) => { if (list && !list.isDestroyed()) list.setSize(Math.max(120, size.width), Math.max(60, size.height)); });
ipcMain.on('toggle', (e, key) => toggle(key));
ipcMain.on('hide', () => toggle('hidden'));
ipcMain.on('quit', () => app.quit());
ipcMain.on('ready', () => {});
ipcMain.handle('send', async (e, id, text) => { try { return await model.send(text, id); } catch (err) { throw new Error(err.message || String(err)); } });
ipcMain.handle('broadcast', (e, text) => model.broadcast(text));

// MARK: model events
model.on('snapshot', snap => { send('snapshot', snap); refreshTray(); });
for (const ev of ['strike', 'treat', 'angry', 'sound']) model.on(ev, (...a) => send(ev, ...a));
model.on('bring-to-front', g => bringToFront(g));
model.on('wake-claude', () => platform.openClaudeTerminal(model.reader.recentProjects(1)[0] || null));
model.on('send-failed', (id, why) => console.warn('send failed', id, why));

// MARK: startup
app.on('second-instance', () => { config.set('hidden', false); applyVisibility(); });
app.on('window-all-closed', e => e.preventDefault());
app.on('will-quit', () => hotkeys.unregisterAll());

app.whenReady().then(async () => {
  lang.setLang(config.get('lang') || 'en');
  swing.needsOption = !!config.get('needsOption');
  if (process.platform === 'linux') await new Promise(r => setTimeout(r, 300));     // transparent visuals need a beat on some WMs
  if (process.platform === 'darwin' && app.dock) app.dock.hide();
  createOverlay();
  createList();
  createTray();
  registerHotkeys();
  model.start();
  startCursorLoop();
  setTimeout(applyVisibility, 400);
  screen.on('display-metrics-changed', () => { if (overlay) { const b = display().workArea; overlay.setBounds(b); overlay.webContents.send('bounds', b); } });

  // Development: WHIPLASH_SNAPSHOT=<folder> saves overlay.png and list.png after 5 s (and quits with WHIPLASH_SNAPSHOT_QUIT=1)
  if (process.env.WHIPLASH_SNAPSHOT) {
    setTimeout(async () => {
      const dir = process.env.WHIPLASH_SNAPSHOT;
      try {
        fs.mkdirSync(dir, { recursive: true });
        for (const [name, w] of [['overlay', overlay], ['list', list]]) {
          if (!w || !w.isVisible()) continue;
          const img = await w.webContents.capturePage();
          fs.writeFileSync(path.join(dir, name + '.png'), img.toPNG());
        }
        console.log('snapshot saved to', dir);
      } catch (e) { console.error('snapshot failed', e); }
      if (process.env.WHIPLASH_SNAPSHOT_QUIT) app.quit();
    }, 5000);
  }
});
