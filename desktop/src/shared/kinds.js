// Which agent is which. Same list, same order and same colors as the macOS app (Sources/Sprites.swift, Monitor.swift).
const sprites = require('./sprites.json');

const KINDS = ['claudeCode', 'claudeApp', 'codex', 'cursor', 'gemini', 'antigravity', 'other'];

const TITLES = {
  claudeCode: 'Claude Code', claudeApp: 'Claude app', codex: 'Codex', cursor: 'Cursor',
  gemini: 'Gemini CLI', antigravity: 'Antigravity', other: 'Other agent',
};

function order(kind) { const i = KINDS.indexOf(kind); return i < 0 ? KINDS.length : i; }
function spriteOf(kind) { return sprites.sprites[sprites.kinds[kind] || 'blob']; }
function barColor(kind) { return sprites.barColors[kind] || sprites.barColors.other; }

/**
 * Port of AgentMatcher.match. path = executable path, name = executable basename (lower-case, no .exe),
 * args = full command line (only looked at for node/python/bun). Returns {kind, isApp} or null.
 */
const INTERPRETERS = new Set(['node', 'bun', 'deno', 'python', 'python3', 'electron']);
function match(path, name, args) {
  const p = path.replace(/\\/g, '/');
  const a = args || '';
  const lower = p.toLowerCase();
  // Claude Code: native binary under ~/.local/share/claude/versions, npm package, or node running cli.js
  if (lower.includes('claude-code') || lower.includes('/claude/versions/') || a.includes('@anthropic-ai/claude-code')
      || / \/?[^ ]*\/bin\/claude( |$)/.test(a) || /[\\/]claude(\.exe)?( |$)/i.test(a) && /node|bun/i.test(name)) {
    return { kind: 'claudeCode', isApp: false };
  }
  if (/\/claude\.app\//i.test(p) || /\/anthropicclaude\//i.test(lower) || name === 'claude' && lower.includes('anthropic')) return { kind: 'claudeApp', isApp: true };
  if (name === 'claude') return { kind: 'claudeCode', isApp: false };

  if (/\/codex\.app\//i.test(p)) return { kind: 'codex', isApp: true };
  if (name === 'codex' || name.startsWith('codex-') || lower.includes('@openai/codex') || a.includes('@openai/codex') || /[\\/]bin[\\/]codex( |$)/.test(a)) {
    return { kind: 'codex', isApp: false };
  }
  if (/\/cursor\.app\//i.test(p) || name === 'cursor' && !a.includes('cursor-agent')) return { kind: 'cursor', isApp: true };
  if (name === 'cursor-agent' || a.includes('cursor-agent')) return { kind: 'cursor', isApp: false };
  if (/\/antigravity\.app\//i.test(p) || name === 'antigravity') return { kind: 'antigravity', isApp: true };
  if (name === 'gemini' || a.includes('@google/gemini-cli') || /[\\/]bin[\\/]gemini( |$)/.test(a)) return { kind: 'gemini', isApp: false };

  const others = new Set(['opencode', 'aider', 'goose', 'amp', 'crush', 'qwen']);
  if (others.has(name) || /[\\/]bin[\\/](aider|amp)( |$)/.test(a) || a.includes('opencode') || a.includes('@qwen-code')) {
    return { kind: 'other', isApp: false };
  }
  return null;
}

module.exports = { KINDS, TITLES, INTERPRETERS, order, spriteOf, barColor, match };
