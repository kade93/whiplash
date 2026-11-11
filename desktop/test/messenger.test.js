const test = require('node:test');
const assert = require('node:assert');
const net = require('net');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { send, SendError } = require('../src/main/messenger');

function pipePath(name) {
  return process.platform === 'win32' ? `\\\\.\\pipe\\whiplash-test-${name}-${process.pid}` : path.join(os.tmpdir(), `whiplash-test-${name}-${process.pid}.sock`);
}

test('send writes auth + user lines and reads the reply (unix socket / named pipe)', async () => {
  const p = pipePath('ok');
  try { fs.unlinkSync(p); } catch {}
  const keyFile = path.join(os.tmpdir(), `whiplash-test-${process.pid}.key`);
  fs.writeFileSync(keyFile, JSON.stringify({ peerToken: 'abc123' }));
  const got = [];
  const server = net.createServer(sock => {
    sock.on('data', d => got.push(d.toString()));
    sock.on('end', () => { sock.end('{"ok":true}\n'); });
  });
  await new Promise(r => server.listen(p, r));
  try {
    const reply = await send('hello', { socketPath: p, keyFile });
    assert.strictEqual(reply, '{"ok":true}');
    const lines = got.join('').trim().split('\n').map(JSON.parse);
    assert.deepStrictEqual(lines[0], { type: 'auth', token: 'abc123' });
    assert.deepStrictEqual(lines[1], { type: 'user', message: { role: 'user', content: 'hello' } });
  } finally { server.close(); fs.unlinkSync(keyFile); }
});

test('send rejects when there is no socket or the session refuses', async () => {
  await assert.rejects(send('x', { socketPath: null }), e => e instanceof SendError && e.code === 'noSocket');
  const p = pipePath('refuse');
  try { fs.unlinkSync(p); } catch {}
  const server = net.createServer(sock => sock.end('{"error":"unauthorized"}\n'));
  await new Promise(r => server.listen(p, r));
  try {
    await assert.rejects(send('x', { socketPath: p, keyFile: '/nonexistent/key' }), e => e.code === 'noToken');
    process.env.WHIPLASH_FAKE_SOCK = p; process.env.WHIPLASH_FAKE_TOKEN = 'zzz';
    await assert.rejects(send('x', { socketPath: p }), e => e.code === 'rejected');
  } finally { delete process.env.WHIPLASH_FAKE_SOCK; delete process.env.WHIPLASH_FAKE_TOKEN; server.close(); }
});
