const test = require('node:test');
const assert = require('node:assert');
const { fold, newTail, encoded, replyTail } = require('../src/main/sessions');

test('encoded cwd matches the projects folder naming', () => {
  assert.strictEqual(encoded('/home/demo/my proj'), '-home-demo-my-proj');
  assert.strictEqual(encoded('C:\\Users\\demo\\proj'), 'C--Users-demo-proj');
});

test('fold: prompt → tool_use → waiting for permission', () => {
  const tail = newTail();
  fold([
    { type: 'user', message: { role: 'user', content: [{ type: 'text', text: 'fix it' }] } },
    { type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Bash', input: { description: 'Run tests' } }] } },
  ], tail);
  assert.strictEqual(tail.waiting, 'permission');
  assert.strictEqual(tail.chore, 'run');
  assert.match(tail.activity, /Running · Run tests/);
});

test('fold: text reply → my turn, tool_result → thinking', () => {
  const tail = newTail();
  fold([{ type: 'assistant', message: { content: [{ type: 'text', text: 'Done.\n\nShall I commit?' }] } }], tail);
  assert.strictEqual(tail.waiting, 'reply');
  assert.strictEqual(tail.lastReply, 'Shall I commit?');
  fold([{ type: 'user', message: { content: [{ type: 'tool_result', content: 'ok' }] } }], tail);
  assert.strictEqual(tail.waiting, 'none');
  assert.strictEqual(tail.chore, 'think');
});

test('fold: AskUserQuestion keeps question and options; cost-state sums tokens', () => {
  const tail = newTail();
  fold([
    { type: 'assistant', message: { content: [{ type: 'tool_use', name: 'AskUserQuestion', input: { questions: [{ question: 'Which?', options: [{ label: 'A' }, { label: 'B' }] }] } }] } },
    { type: 'cost-state', totalCostUSD: 1.5, modelUsage: { m: { inputTokens: 10, outputTokens: 5, cacheReadInputTokens: 999 } }, totalLinesAdded: 3, totalLinesRemoved: 1 },
  ], tail);
  assert.strictEqual(tail.waiting, 'question');
  assert.deepStrictEqual(tail.options, ['A', 'B']);
  assert.strictEqual(tail.tokens, 15);
  assert.strictEqual(tail.cost, 1.5);
  assert.strictEqual(tail.added, 3);
});

test('fold: 429 marks a strike until the assistant answers again', () => {
  const tail = newTail();
  fold([{ type: 'system', subtype: 'api_error', timestamp: new Date().toISOString(), error: { status: 429, rateLimits: { retryAfter: 60 } } },
        { type: 'user', message: { content: 'x' } }], tail);
  assert.ok(tail.strikeUntil > Date.now());
  fold([{ type: 'assistant', message: { content: [{ type: 'text', text: 'back' }] } }], tail);
  assert.strictEqual(tail.strikeUntil, null);
});

test('replyTail skips code blocks and strips bold', () => {
  assert.strictEqual(replyTail('Intro\n\n```\ncode\n```\n\n**All** good'), 'All good');
});
