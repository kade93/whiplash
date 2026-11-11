// Linux: everything comes from /proc. Only this user's processes are listed.
const fs = require('fs');
const os = require('os');
const path = require('path');

const CLK_TCK = 100;                                   // sysconf(_SC_CLK_TCK) is 100 on every mainstream distro
let bootMs = null;
function bootTime() {
  if (bootMs) return bootMs;
  try { const m = /btime (\d+)/.exec(fs.readFileSync('/proc/stat', 'utf8')); if (m) bootMs = Number(m[1]) * 1000; } catch {}
  return bootMs || (Date.now() - os.uptime() * 1000);
}

function readLink(p) { try { return fs.readlinkSync(p); } catch { return ''; } }
function readText(p) { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } }

/** → [{pid, ppid, uid, startMs, cpuMs, memory, name, path, args, cwd}] */
function list() {
  const uid = process.getuid ? process.getuid() : -1;
  const out = [];
  let names;
  try { names = fs.readdirSync('/proc'); } catch { return out; }
  for (const n of names) {
    if (!/^\d+$/.test(n)) continue;
    const pid = Number(n);
    const base = '/proc/' + n;
    const stat = readText(base + '/stat');
    if (!stat) continue;
    const close = stat.lastIndexOf(')');
    const comm = stat.slice(stat.indexOf('(') + 1, close);
    const f = stat.slice(close + 2).split(' ');          // f[0] = state, f[1] = ppid, f[11]=utime, f[12]=stime, f[19]=starttime
    const ppid = Number(f[1]);
    const cpuMs = (Number(f[11]) + Number(f[12])) * 1000 / CLK_TCK;
    const startMs = bootTime() + Number(f[19]) * 1000 / CLK_TCK;
    let puid = -1, rss = 0;
    const status = readText(base + '/status');
    const um = /^Uid:\s+(\d+)/m.exec(status); if (um) puid = Number(um[1]);
    if (uid >= 0 && puid !== uid) continue;
    const rm = /^VmRSS:\s+(\d+) kB/m.exec(status); if (rm) rss = Number(rm[1]) * 1024;
    const exe = readLink(base + '/exe').replace(/ \(deleted\)$/, '');
    const cmdline = readText(base + '/cmdline');
    const argv = cmdline.split('\0').filter(Boolean);
    const name = path.basename(exe || argv[0] || comm);
    out.push({ pid, ppid, uid: puid, startMs, cpuMs, memory: rss, name, path: exe || argv[0] || '', args: argv.join(' '), cwd: null, _base: base });
  }
  return out;
}

function cwd(pid) { return readLink('/proc/' + pid + '/cwd') || null; }

module.exports = { list, cwd };
