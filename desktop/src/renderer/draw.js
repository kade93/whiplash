// Pixel drawing shared by the overlay and the list window. Data comes from window.SPRITES (= shared/sprites.json,
// generated from the Mac app's Sprites.swift). Everything is drawn on a canvas with crisp cells.
(function () {
  const S = window.SPRITES;
  const INK = S.ink;
  const LANG = window.LANG_TABLE || {};
  let lang = 'en';
  window.setLang = l => { lang = l; };
  window.t = en => { if (lang === 'en') return en; const r = LANG[en]; return r ? (lang === 'ko' ? r[0] : r[1]) : en; };

  function spriteColor(sp, ch) {
    switch (ch) { case 'K': case 'E': return INK; case 'B': return sp.body; case 'L': return sp.light; case 'A': return sp.accent; case 'C': return sp.cheek; default: return null; }
  }

  /** Draw a 12×10 critter. opts: {cell, awake, bob, sweat, hot, angry, ox, oy} */
  function drawSprite(ctx, sp, o) {
    const cell = o.cell, cols = sp.rows[0].length, rowCount = sp.rows.length;
    const ox = o.ox, oy = o.oy + (o.bob ? -cell : 0);
    for (let y = 0; y < rowCount; y++) {
      const row = sp.rows[y];
      for (let x = 0; x < cols; x++) {
        const ch = row[x];
        let c = spriteColor(sp, ch);
        if (!c) continue;
        if (o.angry && (ch === 'B' || ch === 'L')) c = '#E04F3A';
        let h = cell, yy = oy + y * cell;
        if (ch === 'E' && !o.awake) { yy += cell * 0.6; h = cell * 0.4; }
        ctx.fillStyle = c;
        ctx.fillRect(ox + x * cell, yy, cell, h);
      }
    }
    const unit = Math.max(1, Math.round(cell / 3));
    const rightX = ox + cols * cell;
    if (!o.awake) {                                   // z
      const z = ['111', '010', '111'];
      ctx.fillStyle = 'rgba(42,36,51,0.55)';
      for (let y = 0; y < 3; y++) for (let x = 0; x < 3; x++) if (z[y][x] === '1') ctx.fillRect(rightX + x * unit, o.oy - cell + 1 + y * unit, unit, unit);
    } else if (o.sweat) {
      ctx.fillStyle = '#6CB8F0';
      ctx.fillRect(rightX, oy + cell, unit * 2, unit * 3);
      if (o.hot) ctx.fillRect(ox - unit * 2, oy + cell * 2, unit * 2, unit * 3);
    }
    if (o.hot) {
      const puffs = o.bob ? [[3, 0, 2], [6, -2, 1.5], [1, -3, 1]] : [[2, -1, 2], [5, 0, 1.5], [7, -3, 1]];
      ctx.fillStyle = 'rgba(128,128,128,0.45)';
      for (const [px, py, sz] of puffs) ctx.fillRect(ox + px * cell, o.oy + py * cell - cell, sz * unit, sz * unit);
    }
  }

  function drawPixels(ctx, rows, cell, ox, oy) {
    for (let y = 0; y < rows.length; y++) for (let x = 0; x < rows[y].length; x++) {
      const c = S.palette[rows[y][x]];
      if (!c) continue;
      ctx.fillStyle = c; ctx.fillRect(ox + x * cell, oy + y * cell, cell, cell);
    }
  }

  /** Tool in hand, rotated with the beat; a tiny whip for delegate */
  function drawTool(ctx, chore, bob, cell, x, y) {
    if (!chore || chore === 'none') return;
    const unit = Math.max(1, Math.round(cell * 0.8));
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate((chore === 'strike' ? (bob ? -8 : 8) : (bob ? -28 : 6)) * Math.PI / 180);
    if (chore === 'delegate') {
      ctx.fillStyle = S.palette.W; ctx.fillRect(0, -unit * 5, unit, unit * 5);
      ctx.strokeStyle = S.palette.D; ctx.lineWidth = Math.max(1, unit / 2);
      ctx.beginPath(); ctx.moveTo(unit, -unit * 5); ctx.quadraticCurveTo(unit * 4, -unit * 8, unit * 6, -unit * 3); ctx.stroke();
    } else {
      const rows = S.tools[chore];
      if (rows) drawPixels(ctx, rows, unit, 0, -rows.length * unit);
    }
    ctx.restore();
  }

  /**
   * One critter tile: sprite + tool + chain + badges. Returns nothing; draws into ctx at (x,y) with the tile size.
   * g: {kind, awake, bob, sweat, hot, chore, angry, onStrike}
   */
  function drawCritter(ctx, g, cell, x, y, flip) {
    const sp = S.sprites[S.kinds[g.kind] || 'blob'];
    const w = cell * 14 + 2, h = cell * 13 + 1;
    ctx.save();
    if (flip) { ctx.translate(x + w, y); ctx.scale(-1, 1); } else ctx.translate(x, y);
    if (g.box) { ctx.fillStyle = g.hot ? '#FFD9D2' : '#E9F3F4'; roundRect(ctx, 0, 0, w, h, cell * 3); ctx.fill(); }
    if (g.angry) { ctx.fillStyle = 'rgba(255,0,0,0.22)'; roundRect(ctx, 0, 0, w, h, cell * 3); ctx.fill(); }
    const ox = Math.round((w - 12 * cell) / 2), oy = Math.round((h - 10 * cell) / 2);
    drawSprite(ctx, sp, { cell, awake: g.awake, bob: g.bob, sweat: g.sweat, hot: g.hot, angry: g.angry, ox, oy });
    if (g.ghost) { ctx.globalCompositeOperation = 'destination-in'; ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.fillRect(-20, -20, w + 40, h + 40); ctx.globalCompositeOperation = 'source-over'; }
    if (g.awake && g.chore !== 'strike') drawPixels(ctx, S.chain, Math.max(1, Math.round(cell * 0.6)), -cell * 1.2, h - S.chain.length * Math.max(1, Math.round(cell * 0.6)) + cell * 0.8);
    if (g.awake || g.chore === 'strike') drawTool(ctx, g.onStrike ? 'strike' : g.chore, g.bob, cell, w - cell * 2, h + cell * 0.5);
    ctx.restore();
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }

  window.WDraw = { drawSprite, drawPixels, drawCritter, drawTool, tileSize: cell => ({ w: cell * 14 + 2, h: cell * 13 + 1 }), barColor: k => S.barColors[k] || S.barColors.other, INK };
})();
