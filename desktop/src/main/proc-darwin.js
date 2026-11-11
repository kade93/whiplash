// macOS: used only while developing the cross-platform app on a Mac (the real Mac app is the Swift one).
// Two `ps` calls: one with comm= (the full executable path, may contain spaces) and one with args=.
const { execFile } = require('child_process');
const path = require('path');

function ps(cols) {
  return new Promise(resolve => execFile('/bin/ps', ['-axo', cols], { maxBuffer: 32 * 1024 * 1024 }, (err, out) => resolve(err ? '' : out)));
}

async function list() {
  const [main, argsOut] = await Promise.all([ps('pid=,ppid=,uid=,lstart=,cputime=,rss=,comm='), ps('pid=,args=')]);
  const args = new Map();
  for (const line of argsOut.split('\n')) { const m = /^\s*(\d+)\s+(.*)$/.exec(line); if (m) args.set(Number(m[1]), m[2]); }
  const uid = process.getuid();
  const rows = [];
  for (const line of main.split('\n')) {
    // pid ppid uid "Mon Nov 10 20:14:05 2026" 00:01:23 rss /path/with spaces/exe
    const m = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+[\d:]+\s+\d{4})\s+(\S+)\s+(\d+)\s+(.*)$/.exec(line);
    if (!m || Number(m[3]) !== uid) continue;
    const [h, mn, s] = m[5].split(':').map(Number);
    const cpuMs = m[5].includes('-') ? 0 : ((h || 0) * 3600 + (mn || 0) * 60 + (s || 0)) * 1000;
    const exe = m[7].trim();
    const pid = Number(m[1]);
    rows.push({ pid, ppid: Number(m[2]), uid, startMs: Date.parse(m[4]) || 0, cpuMs, memory: Number(m[6]) * 1024,
                name: path.basename(exe), path: exe, args: args.get(pid) || exe, cwd: null });
  }
  return rows;
}

function cwd() { return null; }

module.exports = { list, cwd };
