// Windows: a single long-lived PowerShell reads Win32_Process through CIM every time we send it a line.
// One spawn for the whole app instead of one every 2 seconds; a sample is ~100-300 ms of PowerShell time.
const { spawn } = require('child_process');
const path = require('path');

const SCRIPT = `
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) { break }
  $rows = Get-CimInstance Win32_Process | ForEach-Object {
    $start = 0
    if ($_.CreationDate) { $start = [int64]([DateTimeOffset]$_.CreationDate).ToUnixTimeMilliseconds() }
    [pscustomobject]@{
      p = $_.ProcessId; pp = $_.ParentProcessId; n = $_.Name; x = $_.ExecutablePath; c = $_.CommandLine
      t = [int64](($_.UserModeTime + $_.KernelModeTime) / 10000); m = [int64]$_.WorkingSetSize; s = $start
    }
  }
  $json = $rows | ConvertTo-Json -Compress -Depth 2
  [Console]::Out.WriteLine($json)
  [Console]::Out.WriteLine('###END###')
  [Console]::Out.Flush()
}
`;

let child = null;
let buffer = '';
let pending = null;

function start() {
  if (child) return;
  const exe = process.env.SystemRoot ? path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe') : 'powershell.exe';
  child = spawn(exe, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', '-'], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
  child.stdin.write(SCRIPT + '\n');
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', d => {
    buffer += d;
    const i = buffer.indexOf('###END###');
    if (i < 0) return;
    const json = buffer.slice(0, i).trim();
    buffer = buffer.slice(i + 9);
    const p = pending; pending = null;
    if (p) p.resolve(json);
  });
  child.on('exit', () => { child = null; if (pending) { pending.resolve(''); pending = null; } });
}

/** Resolves to [{pid, ppid, uid, startMs, cpuMs, memory, name, path, args, cwd}] */
function list() {
  return new Promise(resolve => {
    start();
    if (!child) return resolve([]);
    if (pending) return resolve([]);                        // previous sample still running: skip this tick
    pending = { resolve: json => resolve(parse(json)) };
    child.stdin.write('go\n');
    setTimeout(() => { if (pending) { pending = null; resolve([]); } }, 8000);
  });
}

function parse(json) {
  if (!json) return [];
  let rows;
  try { rows = JSON.parse(json); } catch { return []; }
  if (!Array.isArray(rows)) rows = [rows];
  return rows.map(r => {
    const exe = r.x || '';
    const name = String(r.n || path.basename(exe)).replace(/\.exe$/i, '');
    return { pid: Number(r.p), ppid: Number(r.pp), uid: -1, startMs: Number(r.s) || 0, cpuMs: Number(r.t) || 0,
             memory: Number(r.m) || 0, name, path: exe, args: r.c || '', cwd: null };
  }).filter(r => r.pid > 0);
}

function cwd() { return null; }                            // no cheap per-process cwd on Windows; sessions carry their own

module.exports = { list, cwd };
