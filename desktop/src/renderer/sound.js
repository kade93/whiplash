// Sounds: the whip and angry .wav files from the Mac app (assets/sounds, copied by tools/prepare-assets.js) plus a few
// tiny synthesized blips for the system sounds the Mac app borrows from macOS (pop, tink, basso, purr).
(function () {
  const base = window.SOUND_BASE || '../../assets/sounds/';
  const files = { whip1: 'whip1.wav', whip2: 'whip2.wav', whip3: 'whip3.wav', angry: 'angry.wav' };
  const cache = {};
  function audio(name) { const a = new Audio(base + files[name]); a.volume = 0.9; return a; }
  function play(name, delay = 0) {
    if (!files[name]) return blip(name);
    const a = (cache[name] && cache[name].paused) ? cache[name] : audio(name);
    cache[name] = a;
    setTimeout(() => { try { a.currentTime = 0; a.play().catch(() => {}); } catch {} }, delay);
  }
  let ctx = null;
  function blip(kind) {
    try {
      ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
      const o = ctx.createOscillator(), g = ctx.createGain();
      const spec = { pop: [880, 0.08, 'sine'], tink: [1760, 0.12, 'triangle'], basso: [110, 0.25, 'sawtooth'], yum: [660, 0.18, 'sine'], glass: [1320, 0.3, 'sine'] }[kind] || [440, 0.1, 'sine'];
      o.type = spec[2]; o.frequency.value = spec[0];
      if (kind === 'yum') o.frequency.linearRampToValueAtTime(990, ctx.currentTime + 0.15);
      g.gain.value = 0.15; g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + spec[1]);
      o.connect(g).connect(ctx.destination); o.start(); o.stop(ctx.currentTime + spec[1]);
    } catch {}
  }
  window.WSound = {
    play,
    chorus(n) { play('whip1'); for (let i = 1; i < Math.min(n, 6); i++) play(i % 2 ? 'whip2' : 'whip3', 60 * i); },
  };
})();
