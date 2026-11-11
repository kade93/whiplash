const test = require('node:test');
const assert = require('node:assert');
const { SwingDetector } = require('../src/main/swing');

function run(points, cb) {
  const hits = { swing: [], pet: [], sweep: [] };
  const d = new SwingDetector({ onSwing: id => hits.swing.push(id), onPet: id => hits.pet.push(id), onSweep: ids => hits.sweep.push(ids) });
  d.setTargets([{ id: 'a', x: 100, y: 100, w: 50, h: 40 }, { id: 'b', x: 300, y: 100, w: 50, h: 40 }]);
  for (const [x, y, t] of points) d.feed({ x, y }, t);
  cb(hits);
}

test('two fast crossings after a dwell whip the critter', () => {
  const pts = [[125, 120, 0], [125, 121, 0.1], [125, 120, 0.2], [125, 121, 0.3]];   // dwell 0.3 s
  pts.push([90, 120, 0.35], [160, 120, 0.40], [90, 120, 0.45]);                  // 70 px / 50 ms = 1400 px/s, crosses twice
  run(pts, h => { assert.deepStrictEqual(h.swing, ['a']); assert.deepStrictEqual(h.pet, []); });
});

test('a pointer merely passing over does nothing', () => {
  run([[0, 120, 0], [500, 120, 0.05]], h => { assert.deepStrictEqual(h.swing, []); assert.deepStrictEqual(h.sweep, []); });
});

test('three slow strokes are a treat', () => {
  const pts = [[95, 120, 0], [95, 120, 0.3]];
  let t = 0.3, x = 95;
  for (const dir of [1, -1, 1]) { for (let i = 0; i < 12; i++) { t += 0.05; x += dir * 5; pts.push([x, 120, t]); } }   // 100 px/s, 95↔155 across the middle (125)
  run(pts, h => { assert.deepStrictEqual(h.pet, ['a']); assert.deepStrictEqual(h.swing, []); });
});
