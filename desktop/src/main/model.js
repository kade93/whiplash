// App state: samples processes and sessions on a timer, and owns whip / treat / megaphone / anger / immunity.
// Port of the parts of Sources/Model.swift that make sense without AppKit. Emits:
//   'snapshot' (snap)              new data for the windows
//   'strike'   (id)                a critter got hit (hop + shake)
//   'treat'    (id)                a critter got a treat (hop + yum)
//   'angry'    (id, line|null)     a critter talks back for 8 s
//   'sound'    (name, n)           play whip1..3 / angry / chorus(n) / pop / tink / basso
const EventEmitter = require('events');
const { ProcessSampler, alive } = require('./processes');
const { SessionReader } = require('./sessions');
const messenger = require('./messenger');
const config = require('./config');
const { t } = require('../shared/lang');

const GHOST_ID = 'ghost:claude';
const BROADCAST_ID = 'broadcast:all';

class Model extends EventEmitter {
  constructor() {
    super();
    this.sampler = new ProcessSampler();
    this.reader = new SessionReader();
    this.snapshot = { groups: [], ncpu: 1, machineBusy: 0, memTotal: 0, memUsed: 0, selfCPU: 0, selfMemory: 0 };
    this.hits = new Map();         // id → [times] for the 8 s streak
    this.angry = new Map();        // id → {until, line}
    this.lastSent = new Map();
    this.immune = new Set(config.get('immune') || []);
    this.demo = !!process.env.WHIPLASH_DEMO;
    this.dry = !!process.env.WHIPLASH_DRY_WHIP;
    this.interval = process.platform === 'win32' ? 3000 : 2000;
    this.visible = true;
    this.sampling = false;
    this.timer = null;
  }

  start() {
    const tick = async () => { await this.sample(); this.timer = setTimeout(tick, this.visible ? this.interval : 15000); };
    tick();
  }
  stop() { clearTimeout(this.timer); this.timer = null; }
  setVisible(v) { if (v === this.visible) return; this.visible = v; if (v) { clearTimeout(this.timer); this.timer = null; this.start(); } }

  async sample() {
    if (this.sampling) return;
    this.sampling = true;
    try {
      const snap = this.demo ? demoSnapshot() : await this.sampler.sample();
      if (!this.demo) this.attachSessions(snap);
      for (const g of snap.groups) {
        g.awake = g.session ? g.session.status === 'busy' : g.cpu >= 0.03;
        g.overloaded = g.cpu >= 1.5 || g.memory >= Math.max(2 * 1024 ** 3, snap.memTotal / 10);
        g.immune = !!(g.session && this.immune.has(g.session.sessionId));
        g.angry = this.isAngry(g.id) ? this.angry.get(g.id).line : null;
        g.onStrike = !!(g.session && g.session.onStrike);
        g.needsYou = !!(g.session && g.session.needsYou);
      }
      if (!snap.groups.some(g => g.kind === 'claudeCode' || g.kind === 'claudeApp')) {
        snap.groups.push({ id: GHOST_ID, kind: 'claudeCode', label: t('Claude (off)'), rootPID: 0, start: 0, dir: null, cpu: 0, memory: 0,
                           processCount: 0, awake: false, session: null, ghost: true, pids: [] });
      }
      delete snap.alive; delete snap.starts;
      this.snapshot = snap;
      this.emit('snapshot', snap);
    } catch (e) { console.error('sample failed', e); }
    this.sampling = false;
  }

  /** Attach Claude Code session info to CLI groups; sessions whose process we couldn't list still get a row. */
  attachSessions(snap) {
    const cli = snap.groups.filter(g => g.id.startsWith('cli:'));
    const pids = cli.map(g => g.rootPID);
    const files = this.reader.listSessionFiles();
    const extra = [];
    for (const f of files) {
      if (pids.includes(f.pid)) continue;
      const seen = snap.alive && snap.alive.size ? snap.alive.has(f.pid) : alive(f.pid);
      if (!seen) continue;
      if (!snap.alive || !snap.alive.size) extra.push(f.pid);           // process listing failed: trust the file
      else if (!snap.alive.has(f.pid)) continue;
      else extra.push(f.pid);                                           // alive but not classified as an agent (rare): still show it
    }
    const sessions = this.reader.read([...pids, ...extra], snap.starts || new Map());
    for (const g of cli) {
      const s = sessions.get(g.rootPID);
      if (!s) continue;
      g.session = s;
      if (s.cwd && (!g.dir || g.label === t('Terminal'))) { g.dir = s.cwd; g.label = baseName(s.cwd); }
    }
    for (const pid of extra) {
      const s = sessions.get(pid);
      if (!s) continue;
      snap.groups.push({ id: 'cli:' + pid, kind: 'claudeCode', label: baseName(s.cwd), rootPID: pid, start: s.startedAt || 0, dir: s.cwd,
                         cpu: 0, memory: 0, processCount: 1, awake: s.status === 'busy', session: s, pids: [pid] });
    }
    snap.groups.sort((a, b) => kindOrder(a.kind) - kindOrder(b.kind) || a.start - b.start);
  }

  group(id) { return this.snapshot.groups.find(g => g.id === id); }

  // MARK: anger and streaks
  hit(id) {
    const now = Date.now();
    const list = (this.hits.get(id) || []).filter(x => now - x < 8000);
    list.push(now);
    this.hits.set(id, list);
    return list.length;
  }
  isAngry(id) { const a = this.angry.get(id); return !!(a && a.until > Date.now()); }
  getAngry(id, line) {
    this.angry.set(id, { until: Date.now() + 8000, line });
    this.emit('angry', id, line);
    this.emit('sound', 'angry');
    this.emit('strike', id);
    setTimeout(() => { const a = this.angry.get(id); if (a && a.until <= Date.now()) { this.angry.delete(id); this.emit('angry', id, null); } }, 8200);
  }

  // MARK: immunity
  isImmune(g) { return !!(g.session && this.immune.has(g.session.sessionId)); }
  toggleImmune(id) {
    const g = this.group(id);
    if (!g || !g.session) return;
    const sid = g.session.sessionId;
    if (this.immune.has(sid)) this.immune.delete(sid); else this.immune.add(sid);
    config.set('immune', [...this.immune]);
    this.emit('sound', this.immune.has(sid) ? 'tink' : 'pop');
    this.sample();
  }

  // MARK: whip
  canWhip(g) {
    if (!g || this.isImmune(g)) return false;
    return true;
  }

  /** Whip one critter. Claude Code sessions get the whip prompt over the socket; others just react. */
  async whip(id, { silent = false } = {}) {
    const g = this.group(id);
    if (!g) return;
    if (this.isImmune(g)) { if (!silent) this.emit('sound', 'tink'); return false; }
    const streak = this.hit(g.id);
    if (g.onStrike) {
      this.getAngry(g.id, streak >= 2 ? t('No quota, I said!!') : t("I'm out of quota!!"));
      return false;
    }
    const s = g.session;
    if (s && s.needsYou && streak >= 2) {                 // it's your turn: it talks back instead
      const rude = streak >= 3;
      let line;
      if (s.waiting === 'question' || s.waiting === 'permission') line = rude ? t('Just say something already!!') : t('You need to tell me what to do!!');
      else if (s.waiting === 'reply') line = rude ? t('Give me work then!!') : t('I need something to do!!');
      else line = rude ? t('Stop hitting me!!') : t('Why are you hitting me?!');
      this.getAngry(g.id, line);
      return false;
    }
    if (!silent) this.emit('sound', 'whip', Math.min(streak, 3));
    this.emit('strike', g.id);
    if (this.demo || this.dry) return true;
    if (g.ghost) { this.emit('wake-claude'); return true; }
    if (g.id.startsWith('app:')) { this.emit('bring-to-front', g); return true; }
    if (s && s.socketPath) {
      try { await messenger.send(config.whipWords(), s); this.lastSent.set(g.id, Date.now()); return true; }
      catch (e) { this.emit('send-failed', g.id, e.message); this.emit('bring-to-front', g); return false; }
    }
    this.emit('bring-to-front', g);                        // no socket (Codex, Gemini …): just bring it forward
    return true;
  }

  whipTargets() { return this.snapshot.groups.filter(g => !g.id.startsWith('app:') && !g.ghost && this.canWhip(g)); }

  whipRandom() {
    const idle = this.whipTargets().filter(g => !g.awake);
    const pool = idle.length ? idle : this.whipTargets();
    if (!pool.length) { this.emit('sound', 'basso'); return; }
    this.whip(pool[Math.floor(Math.random() * pool.length)].id);
  }

  whipAll() {
    const targets = this.whipTargets().filter(g => !g.awake);
    if (!targets.length) { this.emit('sound', 'basso'); return; }
    this.whipMany(targets.map(g => g.id));
  }

  whipMany(ids) {
    let n = 0;
    for (const id of ids) { const g = this.group(id); if (g && this.canWhip(g)) { this.whip(id, { silent: true }); n++; } }
    if (n > 0) this.emit('sound', 'chorus', n);
  }

  // MARK: treats and megaphone
  async treat(id, { silent = false } = {}) {
    const g = this.group(id);
    if (!g || g.ghost) return;
    if (!silent) this.emit('sound', 'yum');
    this.emit('treat', g.id);
    if (this.demo || this.dry || !g.session) return;
    try { await messenger.send(config.treatWords(), g.session); } catch {}
  }
  treatAll() {
    const targets = this.snapshot.groups.filter(g => g.awake && !g.id.startsWith('app:') && !g.ghost);
    if (!targets.length) { this.emit('sound', 'basso'); return; }
    for (const g of targets) this.treat(g.id, { silent: true });
    this.emit('sound', 'yum');
  }

  /** Send free text to one session */
  async send(text, id) {
    const g = this.group(id);
    if (!g || !g.session) throw new messenger.SendError('noSocket');
    const r = await messenger.send(text, g.session);
    this.lastSent.set(g.id, Date.now());
    this.emit('sent', g.id);
    return r;
  }

  /** Megaphone: the same text to every Claude session. Resolves {ok, total}. */
  async broadcast(text) {
    const targets = this.snapshot.groups.filter(g => g.session && !g.ghost);
    let ok = 0;
    await Promise.all(targets.map(async g => { try { await this.send(text, g.id); ok++; } catch {} }));
    return { ok, total: targets.length };
  }
}

function baseName(p) { const parts = p.replace(/[\\/]+$/, '').split(/[\\/]/); return parts[parts.length - 1] || p; }
const ORDER = ['claudeCode', 'claudeApp', 'codex', 'cursor', 'gemini', 'antigravity', 'other'];
function kindOrder(k) { const i = ORDER.indexOf(k); return i < 0 ? 99 : i; }

/** WHIPLASH_DEMO=1: fake critters for screenshots and CI smoke tests */
function demoSnapshot() {
  const mk = (i, kind, label, status, waiting, chore, activity, cpu) => ({
    id: `cli:${1000 + i}`, kind, label, rootPID: 1000 + i, start: i, dir: '/home/demo/' + label, cpu, memory: 300e6 + i * 50e6, processCount: 3, pids: [],
    session: kind === 'claudeCode' ? { pid: 1000 + i, sessionId: 'demo-' + i, cwd: '/home/demo/' + label, name: label, status, waiting, chore, activity,
      lastReply: waiting === 'reply' ? 'Shall I go on with the next step?' : '', question: waiting === 'question' ? 'Which option?' : '', options: waiting === 'question' ? ['A', 'B'] : [],
      costUSD: 1.2 * (i + 1), tokens: 120000 * (i + 1), linesAdded: 40 * i, linesRemoved: 3 * i, socketPath: null, keyFile: null, needsYou: status === 'idle' && waiting !== 'none', onStrike: false, isDesktop: false } : null,
  });
  return { groups: [
    mk(0, 'claudeCode', 'whiplash', 'busy', 'none', 'write', 'Editing · main.js', 0.8),
    mk(1, 'claudeCode', 'shop-app', 'idle', 'reply', 'answer', 'Answering', 0.01),
    mk(2, 'claudeCode', 'docs', 'idle', 'question', 'answer', 'Asking you', 0),
    mk(3, 'codex', 'api', 'busy', 'none', 'none', '', 0.4),
    mk(4, 'gemini', 'site', 'idle', 'none', 'none', '', 0),
    mk(5, 'claudeCode', 'infra', 'busy', 'none', 'run', 'Running · tests', 1.7),
  ], ncpu: 8, machineBusy: 0.35, memTotal: 32e9, memUsed: 14e9, selfCPU: 0.02, selfMemory: 90e6 };
}

module.exports = { Model, GHOST_ID, BROADCAST_ID };
