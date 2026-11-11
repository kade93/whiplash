// Deliver a prompt to a running Claude Code session — port of Sources/Messenger.swift.
// Claude Code listens on the path it writes to the session file as messagingSocketPath:
//   macOS / Linux : a Unix domain socket, e.g. /tmp/cc-socks/<pid>.sock or /run/user/<uid>/cc-socks/<pid>.sock
//   Windows       : a named pipe, e.g. \\.\pipe\cc-msg-<hash>
// Node's net.connect(path) speaks to both. Two JSON lines go in:
//   {"type":"auth","token":"<peerToken>"}
//   {"type":"user","message":{"role":"user","content":"..."}}
// The peerToken is read from ~/.claude/sessions/<pid>.<sha256 of socket path>.key and never stored anywhere else.
const fs = require('fs');
const net = require('net');
const { t, tf } = require('../shared/lang');

class SendError extends Error {
  constructor(code, detail) { super(code); this.code = code; this.detail = detail; }
  get message() {
    switch (this.code) {
      case 'noSocket': return t('This session has no message socket');
      case 'noToken': return t('Couldn\'t read the session key file');
      case 'connect': return tf('Couldn\'t connect to the session (errno %d)', this.detail || 0);
      case 'write': return tf('Dropped while sending (errno %d)', this.detail || 0);
      case 'rejected': return tf('Session refused: %@', this.detail || '');
      default: return this.code;
    }
  }
}

function readToken(keyFile) {
  try {
    const j = JSON.parse(fs.readFileSync(keyFile, 'utf8'));
    return typeof j.peerToken === 'string' ? j.peerToken : null;
  } catch { return null; }
}

/** Resolve socket path and token for a session (env WHIPLASH_FAKE_SOCK / WHIPLASH_FAKE_TOKEN for a fake server) */
function target(session) {
  let path = session.socketPath;
  let token = null;
  if (process.env.WHIPLASH_FAKE_SOCK) { path = process.env.WHIPLASH_FAKE_SOCK; token = process.env.WHIPLASH_FAKE_TOKEN || 'test'; }
  if (!path) throw new SendError('noSocket');
  if (!token) {
    if (!session.keyFile) throw new SendError('noToken');
    token = readToken(session.keyFile);
    if (!token) throw new SendError('noToken');
  }
  return { path, token };
}

/** Send text to the session; resolves with the reply text (may be empty), rejects with SendError */
function send(text, session, { timeout = 3000 } = {}) {
  return new Promise((resolve, reject) => {
    let tgt;
    try { tgt = target(session); } catch (e) { return reject(e); }
    const sock = net.connect(tgt.path);
    const chunks = [];
    let done = false;
    const finish = (fn, v) => { if (done) return; done = true; clearTimeout(timer); sock.destroy(); fn(v); };
    const timer = setTimeout(() => {
      // No reply within the timeout: the message was written, so count it as sent.
      if (chunks.length || sock.writableFinished) finish(resolve, Buffer.concat(chunks).toString('utf8').trim());
      else finish(reject, new SendError('connect', 110));
    }, timeout);
    sock.on('error', e => {
      const errno = e && typeof e.errno === 'number' ? Math.abs(e.errno) : 0;
      finish(reject, new SendError(sock.connecting ? 'connect' : 'write', errno));
    });
    sock.on('connect', () => {
      const payload = JSON.stringify({ type: 'auth', token: tgt.token }) + '\n'
                    + JSON.stringify({ type: 'user', message: { role: 'user', content: text } }) + '\n';
      sock.write(payload, () => sock.end());
    });
    sock.on('data', d => { chunks.push(d); if (Buffer.concat(chunks).length > 64 * 1024) sock.end(); });
    sock.on('close', () => {
      const reply = Buffer.concat(chunks).toString('utf8').trim();
      const low = reply.toLowerCase();
      if (low.includes('unauthorized') || low.includes('"error"')) finish(reject, new SendError('rejected', reply.slice(0, 120)));
      else finish(resolve, reply);
    });
  });
}

module.exports = { send, SendError, readToken };
