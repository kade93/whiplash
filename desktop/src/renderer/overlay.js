// Roaming: every session is a critter on a transparent full-screen overlay. Working critters wander, idle ones sleep,
// critters that need you hop. Drag to move, click to type an instruction, right-click for the menu.
// The whip gesture itself is detected in the main process from the global cursor (see main/swing.js); this page only
// reports critter rectangles and plays the reactions.
(function () {
  const W = window.whiplash;
  const D = window.WDraw;
  const stage = document.getElementById('stage');
  const whipCursor = document.getElementById('whipcursor');
  const SPEED = 26;                  // px/s while wandering
  let bounds = { x: 0, y: 0, width: window.innerWidth, height: window.innerHeight };
  let small = true, box = false;
  let groups = [];
  const critters = new Map();        // id → critter
  let bob = false;
  let hoverId = null;
  let drag = null;

  function cell() { return small ? 1.5 : 2.5; }
  function size() { const t = D.tileSize(cell()); return { w: Math.round(t.w + cell() * 4), h: Math.round(t.h + cell() * 3) }; }

  // MARK: critter elements
  function makeCritter(g) {
    const el = document.createElement('div');
    el.className = 'critter';
    const canvas = document.createElement('canvas');
    el.appendChild(canvas);
    const badge = document.createElement('div'); badge.className = 'badge'; badge.style.display = 'none'; el.appendChild(badge);
    const bubble = document.createElement('div'); bubble.className = 'bubble'; bubble.style.display = 'none'; el.appendChild(bubble);
    const tag = document.createElement('div'); tag.className = 'tag'; el.appendChild(tag);
    stage.appendChild(el);
    const s = size();
    const c = { id: g.id, el, canvas, badge, bubble, tag, g,
                x: 40 + Math.random() * Math.max(10, bounds.width - s.w - 80), y: 40 + Math.random() * Math.max(10, bounds.height - s.h - 120),
                target: null, facingLeft: false, lastHop: 0, bubbleUntil: 0 };
    el.addEventListener('mousedown', e => {
      if (e.button !== 0) return;
      drag = { c, dx: e.clientX - c.x, dy: e.clientY - c.y, moved: false, startX: e.clientX, startY: e.clientY };
      W.send('drag', true);
    });
    el.addEventListener('contextmenu', e => { e.preventDefault(); W.send('context-menu', c.id, { x: e.screenX, y: e.screenY }); });
    el.addEventListener('dblclick', () => W.send('bring-to-front', c.id));
    critters.set(g.id, c);
    return c;
  }

  document.addEventListener('mousemove', e => {
    if (!drag) return;
    if (!drag.moved && Math.hypot(e.clientX - drag.startX, e.clientY - drag.startY) > 3) drag.moved = true;
    if (drag.moved) { drag.c.x = e.clientX - drag.dx; drag.c.y = e.clientY - drag.dy; drag.c.target = null; place(drag.c); }
  });
  document.addEventListener('mouseup', e => {
    if (!drag) return;
    const d = drag; drag = null;
    W.send('drag', false);
    if (!d.moved && e.button === 0 && d.c.g.session) openPrompt(d.c.id);
  });

  function place(c) {
    c.el.style.transform = `translate(${Math.round(c.x)}px, ${Math.round(c.y)}px)`;
  }

  function render(c) {
    const g = c.g, s = size(), k = cell();
    c.canvas.width = s.w; c.canvas.height = s.h;
    c.canvas.style.width = s.w + 'px'; c.canvas.style.height = s.h + 'px';
    const ctx = c.canvas.getContext('2d');
    ctx.clearRect(0, 0, s.w, s.h);
    const t = D.tileSize(k);
    D.drawCritter(ctx, { kind: g.kind, awake: g.awake, bob: g.awake && bob, sweat: g.cpu >= 1, hot: g.overloaded, chore: g.session ? g.session.chore : (g.awake ? 'run' : 'none'),
                         angry: !!g.angry, onStrike: g.onStrike, ghost: g.ghost, box }, k, Math.round(k * 1.5), Math.round(k), c.facingLeft);
    // badge above the head
    let badge = '';
    if (g.immune) badge = '🛡';
    else if (g.onStrike) badge = '✊';
    else if (g.needsYou) badge = g.session.waiting === 'question' ? '?' : g.session.waiting === 'permission' ? '✋' : '!';
    c.badge.textContent = badge; c.badge.style.display = badge ? '' : 'none';
    c.badge.className = 'badge' + (g.immune ? ' shield' : '');
    // name tag
    if (small) { c.tag.style.display = 'none'; }
    else {
      c.tag.style.display = '';
      const name = (g.session && g.session.name) || g.label || '';
      let act = '', cls = '';
      if (g.onStrike) { act = '✊ ' + window.t('On strike'); cls = 'hot'; }
      else if (g.overloaded) { act = `${window.t('Overloaded')} · ${g.cpu.toFixed(1)} ${window.t('cores')}`; cls = 'hot'; }
      else if (g.session) {
        if (g.awake) { act = g.session.activity || window.t('Working'); cls = 'working'; }
        else if (g.needsYou) { act = { reply: window.t('Waiting for your reply'), question: window.t('Asked and waiting'), permission: window.t('Waiting for permission') }[g.session.waiting]; cls = 'waiting'; }
        else act = window.t('Idle');
      } else act = g.awake ? window.t('Working') : window.t('Idle');
      c.tag.innerHTML = `<span class="name"></span><span class="act ${cls}"></span>`;
      c.tag.querySelector('.name').textContent = name;
      c.tag.querySelector('.act').textContent = act;
    }
    place(c);
  }

  // MARK: snapshot
  W.on('snapshot', snap => {
    groups = snap.groups;
    const live = new Set();
    for (const g of groups) {
      live.add(g.id);
      let c = critters.get(g.id);
      if (!c) c = makeCritter(g);
      c.g = g;
      render(c);
    }
    for (const [id, c] of critters) if (!live.has(id)) { c.el.remove(); critters.delete(id); }
    reportTargets();
  });

  W.on('settings', s => {
    const resize = s.critterSmall !== small || s.critterBox !== box;
    small = !!s.critterSmall; box = !!s.critterBox;
    window.setLang(s.lang || 'en');
    if (resize) for (const c of critters.values()) render(c);
  });
  W.on('bounds', b => { bounds = b; });

  // MARK: reactions
  function bubble(c, text, cls, ms) {
    c.bubble.textContent = text; c.bubble.className = 'bubble ' + cls; c.bubble.style.display = '';
    c.bubbleUntil = performance.now() + ms;
    setTimeout(() => { if (performance.now() >= c.bubbleUntil - 5) c.bubble.style.display = 'none'; }, ms);
  }
  function hop(c, shake) {
    c.el.classList.remove('hop', 'shake'); void c.el.offsetWidth;
    c.el.classList.add('hop'); if (shake) c.el.classList.add('shake');
  }
  W.on('strike', id => { const c = critters.get(id); if (!c) return; hop(c, true); if (!c.g.angry) bubble(c, window.t('Ouch!'), '', 900); });
  W.on('treat', id => { const c = critters.get(id); if (!c) return; hop(c, false); bubble(c, '🥕 ' + window.t('Yum!'), 'yum', 1200); });
  W.on('angry', (id, line) => { const c = critters.get(id); if (!c) return; if (line) { c.g.angry = line; bubble(c, '💢 ' + line, 'angry', 8000); } else { c.g.angry = null; c.bubble.style.display = 'none'; } render(c); });
  W.on('sound', (name, n) => { if (name === 'whip') window.WSound.play('whip' + (n || 1)); else if (name === 'chorus') window.WSound.chorus(n || 1); else window.WSound.play(name); });
  W.on('hover', (id, p) => {
    hoverId = id;
    for (const c of critters.values()) c.el.classList.toggle('hover', c.id === id);
    whipCursor.style.display = id ? '' : 'none';
  });
  W.on('cursor', p => { whipCursor.style.left = (p.x - bounds.x + 12) + 'px'; whipCursor.style.top = (p.y - bounds.y - 22) + 'px'; });
  W.on('gather', p => {                               // come here: line up at the cursor, 10 per row
    const list = [...critters.values()], s = size();
    const cols = Math.min(10, Math.max(1, list.length));
    list.forEach((c, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      c.target = { x: p.x - bounds.x - (cols * (s.w + 6)) / 2 + col * (s.w + 6), y: p.y - bounds.y + 30 + row * (s.h + 28), until: Infinity, gather: true };
    });
  });

  // MARK: physics (15 Hz) and the beat (2.5 Hz)
  setInterval(() => { bob = !bob; for (const c of critters.values()) if (c.g.awake) render(c); }, 400);
  let lastTick = performance.now();
  setInterval(() => {
    const now = performance.now(), dt = Math.min(0.2, (now - lastTick) / 1000); lastTick = now;
    const s = size();
    const maxX = bounds.width - s.w - 4, maxY = bounds.height - s.h - (small ? 8 : 40);
    const list = [...critters.values()];
    for (const c of list) {
      if (drag && drag.c === c) continue;
      const g = c.g;
      if (g.needsYou && now - c.lastHop > 2500) { c.lastHop = now; hop(c, false); }
      const wanders = g.awake && !g.ghost;
      if (c.target && (now > c.target.until || !wanders && !c.target.gather)) c.target = null;
      if (!c.target && wanders && Math.random() < 0.02) {
        c.target = { x: Math.random() * maxX, y: Math.random() * maxY, until: now + 15000 + Math.random() * 15000 };
      }
      if (c.target) {
        const dx = c.target.x - c.x, dy = c.target.y - c.y, d = Math.hypot(dx, dy);
        const v = c.target.gather ? SPEED * 4 : SPEED;
        if (d < 2) { if (!c.target.gather) c.target = null; }
        else { const step = Math.min(d, v * dt); c.x += dx / d * step; c.y += dy / d * step; const left = dx < 0; if (left !== c.facingLeft) { c.facingLeft = left; render(c); } }
      }
      // keep apart
      for (const o of list) {
        if (o === c) continue;
        const dx = c.x - o.x, dy = c.y - o.y;
        if (Math.abs(dx) < s.w && Math.abs(dy) < s.h) {
          const push = 20 * dt;
          c.x += (dx === 0 ? (Math.random() - 0.5) : Math.sign(dx)) * push;
          c.y += (dy === 0 ? (Math.random() - 0.5) : Math.sign(dy)) * push * 0.5;
        }
      }
      c.x = Math.max(0, Math.min(maxX, c.x)); c.y = Math.max(0, Math.min(maxY, c.y));
      place(c);
    }
    reportTargets();
  }, 1000 / 15);

  function reportTargets() {
    const s = size();
    const rects = [];
    for (const c of critters.values()) rects.push({ id: c.id, x: bounds.x + c.x, y: bounds.y + c.y, w: s.w, h: s.h });
    const p = document.getElementById('prompt');
    if (p.style.display !== 'none' && p.style.display !== '') {
      const r = p.getBoundingClientRect();
      rects.push({ id: '#prompt', x: bounds.x + r.left, y: bounds.y + r.top, w: r.width, h: r.height });
    }
    W.send('targets', rects);
  }

  // MARK: prompt box
  const prompt = document.getElementById('prompt');
  const input = prompt.querySelector('input');
  const sendBtn = prompt.querySelector('button');
  const status = prompt.querySelector('.status');
  let promptFor = null;
  function openPrompt(id, broadcast = false) {
    promptFor = { id, broadcast };
    const c = critters.get(id);
    const g = c ? c.g : null;
    prompt.querySelector('.title').textContent = broadcast ? `📣 ${window.t('Megaphone')} — ${groups.filter(x => x.session && !x.ghost).length}` : ((g && g.session && g.session.name) || (g && g.label) || '');
    const ctxEl = prompt.querySelector('.context'), chips = prompt.querySelector('.chips');
    ctxEl.textContent = ''; chips.innerHTML = '';
    if (g && g.session) {
      const s = g.session;
      const labels = s.question ? s.options : (s.lastReply && s.status !== 'busy' ? [window.t('Yes, do it'), window.t("Don't"), window.t('Keep going')] : []);
      ctxEl.textContent = s.question ? '❓ ' + s.question : (s.lastReply ? '💬 ' + s.lastReply : '');
      for (const l of labels) { const b = document.createElement('span'); b.className = 'chip'; b.textContent = l; b.onclick = () => { input.value = l; submit(); }; chips.appendChild(b); }
    }
    input.placeholder = broadcast ? window.t('Same message to everyone (⏎ send · esc close)') : window.t('Type an instruction and send (⏎ send · esc close)');
    status.textContent = broadcast ? window.t('Idle sessions read it now, busy ones after their turn') : (g && g.awake ? window.t('Busy — reads this after the current turn') : window.t('Idle · reads right away'));
    status.className = 'status';
    input.value = ''; sendBtn.disabled = false;
    let x = c ? c.x + size().w + 8 : bounds.width / 2 - 160, y = c ? c.y - 10 : bounds.height / 2 - 60;
    x = Math.max(4, Math.min(bounds.width - 330, x)); y = Math.max(4, Math.min(bounds.height - 140, y));
    prompt.style.left = x + 'px'; prompt.style.top = y + 'px'; prompt.style.display = 'block';
    W.send('prompt-open', true);
    setTimeout(() => input.focus(), 30);
    reportTargets();
  }
  function closePrompt() { prompt.style.display = 'none'; promptFor = null; W.send('prompt-open', false); reportTargets(); }
  async function submit() {
    const text = input.value.trim();
    if (!text || !promptFor) return;
    sendBtn.disabled = true; status.className = 'status'; status.textContent = window.t('Sending…');
    try {
      const r = promptFor.broadcast ? await W.invoke('broadcast', text) : await W.invoke('send', promptFor.id, text);
      if (promptFor.broadcast && r.ok === 0) throw new Error(window.t('No session to send to') + ` (${r.ok}/${r.total})`);
      status.className = 'status ok'; status.textContent = window.t('Sent ✓'); input.value = '';
      setTimeout(closePrompt, 700);
    } catch (e) { status.className = 'status err'; status.textContent = e.message || String(e); sendBtn.disabled = false; }
  }
  input.addEventListener('keydown', e => { if (e.key === 'Enter') submit(); else if (e.key === 'Escape') closePrompt(); });
  sendBtn.addEventListener('click', submit);
  W.on('open-prompt', (id, broadcast) => openPrompt(id, broadcast));
  W.on('close-prompt', closePrompt);
  window.addEventListener('blur', () => { if (promptFor) closePrompt(); });
  W.send('ready');
})();
