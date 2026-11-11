// Claude Code session info — port of Sources/Sessions.swift.
// Claude Code keeps ~/.claude/sessions/<pid>.json (title, busy/idle, messaging socket path) while it runs and
// appends the conversation to ~/.claude/projects/<encoded cwd>/<sessionId>.jsonl. Both are only ever read.
const fs = require('fs');
const path = require('path');
const paths = require('./paths');
const { t } = require('../shared/lang');

// Tool name → what the critter holds (Chore)
function choreOf(tool) {
  switch (tool) {
    case 'Read': case 'NotebookRead': return 'read';
    case 'Edit': case 'MultiEdit': case 'Write': case 'NotebookEdit': case 'TodoWrite': return 'write';
    case 'Bash': case 'BashOutput': case 'KillShell': return 'run';
    case 'Grep': case 'Glob': case 'LS': return 'search';
    case 'Agent': case 'Task': return 'delegate';
    case 'WebSearch': case 'WebFetch': return 'web';
    case 'AskUserQuestion': case 'ExitPlanMode': return 'answer';
    default: return tool.startsWith('mcp__') ? 'web' : 'run';
  }
}

function shortName(name) { const p = name.split('__'); return p[p.length - 1] || name; }

function verb(name) {
  switch (name) {
    case 'Read': return t('Reading');
    case 'Edit': case 'MultiEdit': case 'NotebookEdit': return t('Editing');
    case 'Write': return t('Writing');
    case 'Bash': return t('Running');
    case 'Grep': case 'Glob': return t('Searching');
    case 'Agent': case 'Task': return t('Delegating');
    case 'WebSearch': return t('Web searching');
    case 'WebFetch': return t('Reading the web');
    case 'AskUserQuestion': return t('Asking you');
    case 'ExitPlanMode': return t('Waiting for plan approval');
    case 'TodoWrite': return t('Writing todos');
    default: return shortName(name) + t(' in progress');
  }
}

function toolDetail(name, input) {
  const file = k => path.basename(String(input[k] || ''));
  let s;
  switch (name) {
    case 'Bash': s = input.description || input.command || ''; break;
    case 'Read': case 'Edit': case 'MultiEdit': case 'Write': case 'NotebookEdit': s = file('file_path') || file('notebook_path'); break;
    case 'Grep': case 'Glob': s = input.pattern || ''; break;
    case 'Agent': case 'Task': s = input.description || ''; break;
    case 'WebSearch': s = input.query || ''; break;
    case 'WebFetch': try { s = new URL(input.url || '').host; } catch { s = ''; } break;
    case 'AskUserQuestion': case 'ExitPlanMode': s = ''; break;
    default: s = input.description || input.query || '';
  }
  const one = String(s).split(/\r?\n/)[0] || '';
  return one.length > 48 ? one.slice(0, 48) + '…' : one;
}

/** Last paragraph of a reply (no code blocks or tables), at most 200 chars */
function replyTail(text) {
  const paras = text.split('\n\n').map(p => p.trim()).filter(p => p && !p.startsWith('```') && !p.startsWith('|'));
  let p = paras[paras.length - 1];
  if (!p) return '';
  p = p.replace(/\*\*/g, '').replace(/\n/g, ' ');
  if (p.startsWith('- ') || p.startsWith('* ')) p = p.slice(2);
  return p.length > 200 ? '…' + p.slice(-200) : p;
}

function newTail() {
  return { size: 0, lastPrompt: '', lastReply: '', question: '', options: [], aiTitle: '', activity: '',
           chore: 'none', waiting: 'none', cost: 0, tokens: 0, added: 0, removed: 0, strikeUntil: null };
}

/** Fold transcript records (newest last) into the tail summary. Exported for tests. */
function fold(records, tail) {
  let last = { kind: 'none' };
  let touched = false;
  for (const r of records) {
    if (!r || typeof r !== 'object') continue;
    switch (r.type) {
      case 'last-prompt': if (typeof r.lastPrompt === 'string') tail.lastPrompt = r.lastPrompt; break;
      case 'ai-title': if (typeof r.aiTitle === 'string') tail.aiTitle = r.aiTitle; break;
      case 'system': {
        if (r.subtype !== 'api_error' || !r.error || typeof r.error !== 'object') break;
        const e = r.error;
        const status = Number(e.status) || 0;
        const text = String(e.formatted || '').toLowerCase();
        const limits = e.rateLimits && typeof e.rateLimits === 'object' ? e.rateLimits : null;
        if (status === 429 || limits || text.includes('rate limit') || text.includes('usage limit')) {
          let until = Date.now() + 3600e3;
          if (limits) {
            const n = Number(limits.resetsAt ?? limits.resets_at);
            const sec = Number(limits.retryAfter ?? limits.retry_after);
            if (n) until = n > 1e12 ? n : n * 1000;
            else if (sec) until = Date.now() + sec * 1000;
          }
          if (r.timestamp) { const when = Date.parse(r.timestamp); if (when && Date.now() - when > 6 * 3600e3) break; }
          tail.strikeUntil = until;
        }
        break;
      }
      case 'cost-state': {
        if (typeof r.totalCostUSD === 'number') tail.cost = r.totalCostUSD;
        if (r.modelUsage && typeof r.modelUsage === 'object') {
          let n = 0;
          for (const u of Object.values(r.modelUsage)) {
            if (!u || typeof u !== 'object') continue;
            for (const k of ['inputTokens', 'outputTokens', 'cacheCreationInputTokens']) n += Number(u[k]) || 0;
          }
          if (n > 0) tail.tokens = n;
        }
        if (typeof r.totalLinesAdded === 'number') tail.added = r.totalLinesAdded;
        if (typeof r.totalLinesRemoved === 'number') tail.removed = r.totalLinesRemoved;
        break;
      }
      case 'assistant': case 'user': {
        if (r.isSidechain === true || r.isMeta === true) continue;
        const m = r.message;
        if (!m || typeof m !== 'object') continue;
        touched = true;
        if (r.type === 'assistant') tail.strikeUntil = null;
        const blocks = Array.isArray(m.content) ? m.content : null;
        if (r.type === 'user') {
          if (blocks && blocks.some(b => b && b.type === 'tool_result')) last = { kind: 'toolResult' };
          else { last = { kind: 'prompt' }; tail.lastReply = ''; tail.question = ''; tail.options = []; }
        } else if (blocks) {
          for (const b of blocks) {
            if (!b) continue;
            if (b.type === 'tool_use') {
              const name = typeof b.name === 'string' ? b.name : '?';
              const input = b.input && typeof b.input === 'object' ? b.input : {};
              last = { kind: 'tool', name, detail: toolDetail(name, input) };
              if (name === 'AskUserQuestion' && Array.isArray(input.questions) && input.questions[0]) {
                const q = input.questions[0];
                tail.question = String(q.question || '');
                tail.options = (Array.isArray(q.options) ? q.options : []).map(o => o && o.label).filter(Boolean);
              } else if (name === 'ExitPlanMode') {
                tail.question = t('I drafted a plan. Go ahead with it?');
                tail.options = [t('Go ahead'), t('Revise the plan')];
              } else { tail.question = ''; tail.options = []; }
            } else if (b.type === 'text' && typeof b.text === 'string' && b.text.trim()) {
              last = { kind: 'text' };
              tail.lastReply = replyTail(b.text);
            }
          }
        }
        break;
      }
      default: break;
    }
  }
  if (!touched) return tail;
  switch (last.kind) {
    case 'none': tail.activity = ''; tail.waiting = 'none'; tail.chore = 'none'; break;
    case 'prompt': tail.activity = t('Reading the prompt'); tail.waiting = 'none'; tail.chore = 'read'; break;
    case 'toolResult': tail.activity = t('Thinking'); tail.waiting = 'none'; tail.chore = 'think'; break;
    case 'text': tail.activity = t('Answering'); tail.waiting = 'reply'; tail.chore = 'answer'; break;
    case 'tool':
      tail.activity = last.detail ? `${verb(last.name)} · ${last.detail}` : verb(last.name);
      tail.waiting = (last.name === 'AskUserQuestion' || last.name === 'ExitPlanMode') ? 'question' : 'permission';
      tail.chore = choreOf(last.name);
      break;
  }
  return tail;
}

/** Project folder name = cwd with every non-ASCII-alphanumeric replaced by '-' */
function encoded(cwd) { return cwd.replace(/[^A-Za-z0-9]/g, '-'); }

class SessionReader {
  constructor() { this.tails = new Map(); this.transcripts = new Map(); this.recentCache = null; }

  /** List live session files: [{pid, json}] */
  listSessionFiles() {
    let names;
    try { names = fs.readdirSync(paths.sessionsDir); } catch { return []; }
    const out = [];
    for (const n of names) {
      const m = /^(\d+)\.json$/.exec(n);
      if (!m) continue;
      try {
        const j = JSON.parse(fs.readFileSync(path.join(paths.sessionsDir, n), 'utf8'));
        if (j && typeof j.sessionId === 'string' && typeof j.cwd === 'string') out.push({ pid: Number(m[1]), json: j, keyFile: this.keyFileFor(names, m[1]) });
      } catch {}
    }
    return out;
  }

  keyFileFor(names, pid) {
    const k = names.find(n => n.startsWith(pid + '.') && n.endsWith('.key'));
    return k ? path.join(paths.sessionsDir, k) : null;
  }

  /**
   * Sessions for the given live root pids. starts: pid → process start (ms since epoch) when known.
   * Returns Map pid → session.
   */
  read(pids, starts = new Map()) {
    const out = new Map();
    const live = new Set();
    const files = this.listSessionFiles();
    for (const { pid, json: j, keyFile } of files) {
      if (!pids.includes(pid)) continue;
      const startedMs = Number(j.startedAt) || 0;
      const procStart = starts.get(pid);
      if (procStart && startedMs > 0 && procStart - startedMs > 10 * 60e3) continue;   // stale file from an earlier boot
      const s = {
        pid, sessionId: j.sessionId, cwd: j.cwd,
        name: typeof j.name === 'string' ? j.name : '',
        status: ['busy', 'idle'].includes(j.status) ? j.status : 'unknown',
        startedAt: startedMs > 0 ? startedMs : null,
        statusSince: Number(j.statusUpdatedAt) || null,
        entrypoint: typeof j.entrypoint === 'string' ? j.entrypoint : '',
        socketPath: typeof j.messagingSocketPath === 'string' ? j.messagingSocketPath : null,
        keyFile,
        lastPrompt: '', lastReply: '', question: '', options: [], activity: '', chore: 'none', waiting: 'none',
        costUSD: 0, tokens: 0, linesAdded: 0, linesRemoved: 0, transcript: null, strikeUntil: null,
      };
      live.add(s.sessionId);
      const tr = this.transcript(s.sessionId, s.cwd);
      if (tr) {
        s.transcript = tr;
        const tail = this.refreshTail(s.sessionId, tr);
        Object.assign(s, { lastPrompt: tail.lastPrompt, lastReply: tail.lastReply, question: tail.question, options: tail.options,
                           activity: tail.activity, chore: tail.chore, waiting: tail.waiting, costUSD: tail.cost, tokens: tail.tokens,
                           linesAdded: tail.added, linesRemoved: tail.removed, strikeUntil: tail.strikeUntil });
        if (!s.name) s.name = tail.aiTitle;
      }
      s.onStrike = !!(s.strikeUntil && s.strikeUntil > Date.now());
      s.needsYou = s.status === 'idle' && s.waiting !== 'none';
      s.isDesktop = s.entrypoint === 'claude-desktop';
      out.set(pid, s);
    }
    for (const k of [...this.tails.keys()]) if (!live.has(k)) this.tails.delete(k);
    for (const k of [...this.transcripts.keys()]) if (!live.has(k)) this.transcripts.delete(k);
    return out;
  }

  transcript(sessionId, cwd) {
    if (this.transcripts.has(sessionId)) return this.transcripts.get(sessionId);
    const name = sessionId + '.jsonl';
    let found = null;
    const direct = path.join(paths.projectsDir, encoded(cwd), name);
    if (fs.existsSync(direct)) found = direct;
    else {
      try {
        for (const d of fs.readdirSync(paths.projectsDir)) {
          const p = path.join(paths.projectsDir, d, name);
          if (fs.existsSync(p)) { found = p; break; }
        }
      } catch {}
    }
    this.transcripts.set(sessionId, found);
    return found;
  }

  /** Re-read the tail only when the file size changed (64 KB; 512 KB the first time) */
  refreshTail(sessionId, file) {
    const tail = this.tails.get(sessionId) || newTail();
    let size = 0;
    try { size = fs.statSync(file).size; } catch { return tail; }
    if (size === tail.size) return tail;
    const first = !this.tails.has(sessionId);
    const records = readRecords(file, size, first ? 512 * 1024 : 64 * 1024);
    tail.size = size;
    fold(records, tail);
    this.tails.set(sessionId, tail);
    return tail;
  }

  /** Recent project folders (newest transcript first), read from the first "cwd" in each folder's newest .jsonl */
  recentProjects(limit = 8) {
    if (this.recentCache && Date.now() - this.recentCache.at < 60e3) return this.recentCache.dirs;
    const found = [];
    try {
      for (const d of fs.readdirSync(paths.projectsDir)) {
        const dir = path.join(paths.projectsDir, d);
        let files;
        try { files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')); } catch { continue; }
        let newest = null, newestM = 0;
        for (const f of files) { try { const m = fs.statSync(path.join(dir, f)).mtimeMs; if (m > newestM) { newestM = m; newest = path.join(dir, f); } } catch {} }
        if (!newest) continue;
        const head = readHead(newest, 16 * 1024);
        const m = /"cwd":"((?:[^"\\]|\\.)*)"/.exec(head);
        if (!m) continue;
        let cwd; try { cwd = JSON.parse('"' + m[1] + '"'); } catch { continue; }
        if (fs.existsSync(cwd) && !found.some(x => x[0] === cwd)) found.push([cwd, newestM]);
      }
    } catch {}
    const dirs = found.sort((a, b) => b[1] - a[1]).slice(0, limit).map(x => x[0]);
    this.recentCache = { at: Date.now(), dirs };
    return dirs;
  }
}

function readHead(file, bytes) {
  let fd;
  try { fd = fs.openSync(file, 'r'); const buf = Buffer.alloc(bytes); const n = fs.readSync(fd, buf, 0, bytes, 0); return buf.toString('utf8', 0, n); }
  catch { return ''; } finally { if (fd !== undefined) fs.closeSync(fd); }
}

function readRecords(file, size, bytes) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
    const offset = size > bytes ? size - bytes : 0;
    const len = size - offset;
    const buf = Buffer.alloc(len);
    const n = fs.readSync(fd, buf, 0, len, offset);
    let lines = buf.toString('utf8', 0, n).split('\n').filter(l => l.length);
    if (offset > 0 && lines.length) lines.shift();          // line cut in the middle
    const out = [];
    for (const l of lines) { try { const j = JSON.parse(l); if (j && typeof j === 'object') out.push(j); } catch {} }
    return out;
  } catch { return []; } finally { if (fd !== undefined) fs.closeSync(fd); }
}

// Time and money
function fmtAgo(ms) {
  if (!ms) return '';
  const s = Math.floor((Date.now() - ms) / 1000);
  if (s < 60) return t('just now');
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ${Math.floor(s % 3600 / 60)}m`;
  return `${Math.floor(s / 86400)}d`;
}
function fmtTokens(n) { if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e3) return Math.floor(n / 1e3) + 'k'; return String(n); }
function fmtUSD(v) { if (v <= 0) return ''; if (v < 1) return Math.round(v * 100) + '¢'; if (v < 100) return '$' + v.toFixed(1); return '$' + Math.round(v); }

module.exports = { SessionReader, fold, newTail, encoded, choreOf, replyTail, fmtAgo, fmtTokens, fmtUSD };
