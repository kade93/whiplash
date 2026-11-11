// The Whiplash window (compact list view): critters in rows of N, CPU and memory bars. Click a tile to whip it,
// right-click for the menu, stroke across a tile fast for the whip gesture (detected in the main process).
(function () {
  const W = window.whiplash, D = window.WDraw;
  const grid = document.getElementById('grid');
  let perRow = 10, bob = false, groups = [], snap = null;
  const tiles = new Map();
  let winPos = { x: 0, y: 0 };

  function fmtBytes(b) { if (b >= 1024 ** 3) return (b / 1024 ** 3).toFixed(1) + ' GB'; return Math.round(b / 1024 ** 2) + ' MB'; }

  function renderTile(tile, g) {
    const k = 2.2, t = D.tileSize(k);
    const cv = tile.canvas;
    cv.width = Math.round(t.w + k * 4); cv.height = Math.round(t.h + k * 3);
    const ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, cv.width, cv.height);
    D.drawCritter(ctx, { kind: g.kind, awake: g.awake, bob: g.awake && bob, sweat: g.cpu >= 1, hot: g.overloaded, chore: g.session ? g.session.chore : (g.awake ? 'run' : 'none'),
                         angry: !!g.angry, onStrike: g.onStrike, ghost: g.ghost, box: true }, k, Math.round(k * 1.5), Math.round(k), false);
    let badge = g.immune ? '🛡' : g.onStrike ? '✊' : g.needsYou ? ({ question: '?', permission: '✋' }[g.session.waiting] || '!') : '';
    tile.badge.textContent = badge; tile.badge.style.display = badge ? '' : 'none';
    tile.el.classList.toggle('hot', !!g.overloaded);
    const s = g.session;
    tile.el.title = s ? `${s.name || g.label}\n${g.label} · ${s.activity || (g.awake ? window.t('Working') : window.t('Idle'))}\nCPU ${g.cpu.toFixed(2)} · ${fmtBytes(g.memory)}` : `${g.label} (${g.kind})\nCPU ${g.cpu.toFixed(2)} · ${fmtBytes(g.memory)}`;
  }

  function makeTile(g) {
    const el = document.createElement('div'); el.className = 'tile';
    const canvas = document.createElement('canvas'); el.appendChild(canvas);
    const badge = document.createElement('div'); badge.className = 'badge'; el.appendChild(badge);
    const bubble = document.createElement('div'); bubble.className = 'bubble'; bubble.style.display = 'none'; el.appendChild(bubble);
    el.addEventListener('click', () => W.send('whip', g.id));
    el.addEventListener('contextmenu', e => { e.preventDefault(); W.send('context-menu', g.id, { x: e.screenX, y: e.screenY }); });
    el.addEventListener('dblclick', e => e.stopPropagation());
    grid.appendChild(el);
    const t = { el, canvas, badge, bubble, g };
    tiles.set(g.id, t);
    return t;
  }

  W.on('snapshot', s => {
    snap = s; groups = s.groups;
    const live = new Set();
    for (const g of groups) { live.add(g.id); let t = tiles.get(g.id); if (!t) t = makeTile(g); t.g = g; renderTile(t, g); }
    for (const [id, t] of tiles) if (!live.has(id)) { t.el.remove(); tiles.delete(id); }
    grid.style.gridTemplateColumns = `repeat(${Math.min(perRow, Math.max(1, groups.length))}, 44px)`;
    const working = groups.filter(g => g.awake && !g.ghost).length, need = groups.filter(g => g.needsYou).length, hot = groups.filter(g => g.overloaded).length;
    const real = groups.filter(g => !g.ghost).length;
    document.getElementById('count').innerHTML = real ? `${real} · ${working} ${window.t('working')}${need ? ` · <b>${need} ${window.t('need you')}</b>` : ''}${hot ? ` · <span style="color:#FF6B5B">${hot} ${window.t('overloaded')}</span>` : ''}` : window.t('No agents running right now');
    // bars
    const agentCPU = groups.reduce((a, g) => a + g.cpu, 0) / Math.max(1, s.ncpu);
    const other = Math.max(0, s.machineBusy - agentCPU);
    document.getElementById('cpuBar').innerHTML = groups.map(g => `<i style="width:${(g.cpu / s.ncpu * 100).toFixed(2)}%;background:${D.barColor(g.kind)}"></i>`).join('') + `<i style="width:${(other * 100).toFixed(1)}%;background:#777"></i>`;
    document.getElementById('cpuText').textContent = `${Math.round(s.machineBusy * 100)}%`;
    const agentMem = groups.reduce((a, g) => a + g.memory, 0);
    const otherMem = Math.max(0, s.memUsed - agentMem);
    document.getElementById('memBar').innerHTML = groups.map(g => `<i style="width:${(g.memory / s.memTotal * 100).toFixed(2)}%;background:${D.barColor(g.kind)}"></i>`).join('') + `<i style="width:${(otherMem / s.memTotal * 100).toFixed(1)}%;background:#777"></i>`;
    document.getElementById('memText').textContent = `${fmtBytes(s.memUsed)} / ${fmtBytes(s.memTotal)}`;
    document.getElementById('memLabel').textContent = window.t('Memory');
    document.getElementById('foot').textContent = `Whiplash · CPU ${(s.selfCPU * 100 / Math.max(1, s.ncpu)).toFixed(1)}% · ${fmtBytes(s.selfMemory)}`;
    requestAnimationFrame(() => { fit(); reportTargets(); });
  });

  W.on('settings', s => { perRow = s.compactPerRow || 10; window.setLang(s.lang || 'en'); if (snap) grid.style.gridTemplateColumns = `repeat(${Math.min(perRow, Math.max(1, groups.length))}, 44px)`; requestAnimationFrame(fit); });
  W.on('bounds', b => { winPos = b; reportTargets(); });
  W.on('strike', id => { const t = tiles.get(id); if (!t) return; t.el.classList.remove('hop'); void t.el.offsetWidth; t.el.classList.add('hop'); });
  W.on('treat', id => { const t = tiles.get(id); if (!t) return; t.el.classList.remove('hop'); void t.el.offsetWidth; t.el.classList.add('hop'); bub(t, '🥕'); });
  W.on('angry', (id, line) => { const t = tiles.get(id); if (!t) return; t.g.angry = line; if (line) bub(t, '💢 ' + line, 8000); renderTile(t, t.g); });
  W.on('hover', id => { for (const t of tiles.values()) t.el.classList.toggle('hover', t.g.id === id); });
  W.on('sound', (name, n) => { if (name === 'whip') window.WSound.play('whip' + (n || 1)); else if (name === 'chorus') window.WSound.chorus(n || 1); else window.WSound.play(name); });
  function bub(t, text, ms = 1000) { t.bubble.textContent = text; t.bubble.style.display = ''; clearTimeout(t.bt); t.bt = setTimeout(() => t.bubble.style.display = 'none', ms); }

  setInterval(() => { bob = !bob; for (const t of tiles.values()) if (t.g.awake) renderTile(t, t.g); }, 400);

  function fit() {
    const p = document.getElementById('panel').getBoundingClientRect();
    W.send('fit', { width: Math.ceil(p.width) + 2, height: Math.ceil(p.height) + 2 });
  }
  function reportTargets() {
    const rects = [];
    for (const t of tiles.values()) { const r = t.el.getBoundingClientRect(); rects.push({ id: t.g.id, x: winPos.x + r.left, y: winPos.y + r.top, w: r.width, h: r.height }); }
    W.send('targets', rects);
  }
  setInterval(reportTargets, 1000);
  document.querySelector('#lights .r').addEventListener('click', e => W.send(e.altKey ? 'hide' : 'quit'));
  document.querySelector('#lights .y').addEventListener('click', () => W.send('toggle', 'roaming'));
  document.querySelector('#lights .g').addEventListener('click', () => W.send('toggle', 'roaming'));
  document.getElementById('panel').addEventListener('dblclick', () => W.send('toggle', 'roaming'));
  W.send('ready');
})();
