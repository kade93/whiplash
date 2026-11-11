// Finds agent processes, attaches every child (shells, MCP servers, builds) to its nearest agent ancestor and sums
// CPU and memory per session — port of ProcessSampler in Sources/Monitor.swift.
const os = require('os');
const path = require('path');
const kinds = require('../shared/kinds');
const { t } = require('../shared/lang');

const backend = process.platform === 'win32' ? require('./proc-win') : process.platform === 'linux' ? require('./proc-linux') : require('./proc-darwin');

class ProcessSampler {
  constructor() {
    this.metaCache = new Map();      // "pid:start" → {kind, isApp}
    this.labelCache = new Map();
    this.lastCPU = new Map();        // "pid:start" → cpuMs
    this.lastWall = 0;
    this.lastCpus = null;
    this.home = os.homedir();
  }

  classify(p) {
    const name = p.name.toLowerCase().replace(/\.exe$/, '');
    const args = (kinds.INTERPRETERS.has(name) || name.startsWith('python')) ? p.args : '';
    const m = kinds.match(p.path, name, args);
    return m ? { kind: m.kind, isApp: m.isApp } : { kind: null, isApp: false };
  }

  machineBusy() {
    const cpus = os.cpus();
    let busy = 0, total = 0;
    for (const c of cpus) { const tm = c.times; busy += tm.user + tm.nice + tm.sys; total += tm.user + tm.nice + tm.sys + tm.idle + tm.irq; }
    const last = this.lastCpus; this.lastCpus = { busy, total };
    if (!last || total <= last.total) return 0;
    return Math.min(1, (busy - last.busy) / (total - last.total));
  }

  async sample() {
    const now = Date.now();
    const wall = this.lastWall ? now - this.lastWall : 0;
    this.lastWall = now;
    const procs = await backend.list();

    const byPid = new Map();
    const parent = new Map();
    const keyOf = new Map();
    const metaOf = new Map();
    for (const p of procs) {
      if (p.pid <= 0) continue;
      const key = `${p.pid}:${p.startMs}`;
      byPid.set(p.pid, p); parent.set(p.pid, p.ppid); keyOf.set(p.pid, key);
      let m = this.metaCache.get(key);
      if (!m) { m = this.classify(p); this.metaCache.set(key, m); }
      metaOf.set(p.pid, m);
    }

    // 2) attach each process to its nearest agent ancestor
    const memo = new Map();
    const groupInfo = new Map();   // key → {kind, root}
    const groupKey = pid => {
      const chain = [];
      let cur = pid, result = null;
      while (chain.length < 128) {
        if (memo.has(cur)) { result = memo.get(cur); break; }
        chain.push(cur);
        const m = metaOf.get(cur);
        if (m && m.kind) {
          if (m.isApp) {
            const k = 'app:' + m.kind;
            if (!groupInfo.has(k)) groupInfo.set(k, { kind: m.kind, root: cur });
            result = k;
          } else {
            let root = cur, hops = 0;
            while (hops < 64) {
              const p = parent.get(root);
              if (!(p > 1) || p === root) break;
              const pm = metaOf.get(p);
              if (!pm || pm.kind !== m.kind || pm.isApp) break;
              root = p; hops++;
            }
            const k = 'cli:' + root;
            groupInfo.set(k, { kind: m.kind, root });
            result = k;
          }
          break;
        }
        const p = parent.get(cur);
        if (!(p > 1) || p === cur || !metaOf.has(p)) break;
        cur = p;
      }
      for (const c of chain) memo.set(c, result);
      return result;
    };

    // 3) sum CPU and memory
    const acc = new Map();
    const newCPU = new Map();
    const me = process.pid;
    const snap = { groups: [], ncpu: os.cpus().length || 1, machineBusy: 0, memTotal: os.totalmem(), memUsed: 0, selfCPU: 0, selfMemory: 0, starts: new Map() };
    for (const [pid, key] of keyOf) {
      const gk = groupKey(pid);
      const p = byPid.get(pid);
      const isMe = pid === me || parent.get(pid) === me && !gk;      // Electron helpers count as "me"
      if (!gk && !isMe) continue;
      newCPU.set(key, p.cpuMs);
      let cores = 0;
      const prev = this.lastCPU.get(key);
      if (wall > 0 && prev !== undefined && p.cpuMs >= prev) cores = (p.cpuMs - prev) / wall;
      if (isMe) { snap.selfCPU += cores; snap.selfMemory += p.memory; if (!gk) continue; }
      const gi = groupInfo.get(gk);
      if (!gi) continue;
      let g = acc.get(gk);
      if (!g) {
        const rootP = byPid.get(gi.root);
        const ld = this.label(gi.root, rootP, gk.startsWith('app:'));
        g = { id: gk, kind: gi.kind, label: ld.label, rootPID: gi.root, start: rootP ? rootP.startMs : 0, dir: ld.dir,
              cpu: 0, memory: 0, processCount: 0, awake: false, session: null, pids: [] };
        snap.starts.set(gi.root, g.start);
      }
      g.cpu += cores; g.memory += p.memory; g.processCount += 1; g.pids.push(pid);
      acc.set(gk, g);
    }
    this.lastCPU = newCPU;
    const live = new Set(keyOf.values());
    for (const k of [...this.metaCache.keys()]) if (!live.has(k)) this.metaCache.delete(k);
    for (const k of [...this.labelCache.keys()]) if (!live.has(k)) this.labelCache.delete(k);

    snap.groups = [...acc.values()].sort((a, b) => kinds.order(a.kind) - kinds.order(b.kind) || a.start - b.start);
    snap.machineBusy = this.machineBusy();
    snap.memUsed = os.totalmem() - os.freemem();
    snap.alive = new Set(byPid.keys());
    return snap;
  }

  label(root, p, isApp) {
    if (isApp) return { label: t('app'), dir: null };
    if (!p) return { label: '', dir: null };
    const key = `${p.pid}:${p.startMs}`;
    const c = this.labelCache.get(key);
    if (c) return c;
    let l = t('Terminal');
    const dir = backend.cwd(root);
    if (dir) l = dir === this.home ? '~' : dir === '/' ? '/' : path.basename(dir);
    const r = { label: l, dir };
    this.labelCache.set(key, r);
    return r;
  }
}

/** Is the pid alive? (works on Windows too) */
function alive(pid) { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } }

module.exports = { ProcessSampler, alive };
