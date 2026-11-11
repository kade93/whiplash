// The whip gesture, port of FloatingPanel.trackSwing in Sources/App.swift, fed by the global cursor position
// (polled from the main process, so it works whether or not the overlay window gets mouse events).
//   whip : rest the pointer on a critter for 0.25 s, then cross its middle line twice within 0.8 s at 400 px/s or more
//   treat: same, but slowly (30–180 px/s) three times within 2.5 s
//   sweep: one fast pass (≥700 px/s) across several critters in a row whips them all at once
class SwingDetector {
  constructor({ onSwing, onPet, onSweep, onHover }) {
    this.onSwing = onSwing; this.onPet = onPet; this.onSweep = onSweep; this.onHover = onHover;
    this.targets = new Map();        // id → {x, y, w, h} in screen coordinates
    this.enteredAt = new Map();
    this.passes = new Map();
    this.pets = new Map();
    this.lastSwing = new Map();
    this.lastPet = new Map();
    this.last = null;
    this.hover = null;
    this.needsOption = false;
    this.optionHeld = false;
    this.sweepTrail = [];
    this.sweepHits = [];
    this.sweepCooldownUntil = 0;
  }

  setTargets(list) {
    this.targets = new Map(list.map(r => [r.id, r]));
    for (const id of [...this.enteredAt.keys()]) if (!this.targets.has(id)) this.enteredAt.delete(id);
  }

  /** Which target contains the point (inflated by `pad`) */
  hit(p, pad = 0) {
    for (const [id, r] of this.targets) {
      if (p.x >= r.x - pad && p.x <= r.x + r.w + pad && p.y >= r.y - pad && p.y <= r.y + r.h + pad) return id;
    }
    return null;
  }

  /** Feed one cursor sample. t in seconds. */
  feed(p, t) {
    const last = this.last;
    this.last = { t, p };
    const over = this.hit(p);
    if (over !== this.hover) { this.hover = over; this.onHover && this.onHover(over, p); }
    for (const [id, r] of this.targets) {
      if (!this.enteredAt.has(id) && p.x >= r.x - 28 && p.x <= r.x + r.w + 28 && p.y >= r.y - 28 && p.y <= r.y + r.h + 28) this.enteredAt.set(id, t);
      else if (this.enteredAt.has(id) && !(p.x >= r.x - 60 && p.x <= r.x + r.w + 60 && p.y >= r.y - 60 && p.y <= r.y + r.h + 60)) this.enteredAt.delete(id);
    }
    if (!this.targets.size || !last || t <= last.t || t - last.t > 0.2) return;
    if (this.needsOption && !this.optionHeld) return;
    const dx = p.x - last.p.x, dy = p.y - last.p.y;
    const speed = Math.hypot(dx, dy) / (t - last.t);

    if (speed >= 30 && speed < 180) {                          // petting
      for (const [id, r] of this.targets) {
        const midX = r.x + r.w / 2;
        const ax = last.p.x - midX, bx = p.x - midX;
        const midY = (p.y + last.p.y) / 2;
        if (!(midY >= r.y - 10 && midY <= r.y + r.h + 10)) continue;
        if (!((ax < 0 && bx >= 0) || (ax > 0 && bx <= 0))) continue;
        const entered = this.enteredAt.get(id);
        if (entered === undefined || t - entered < 0.25) continue;
        let list = (this.pets.get(id) || []).filter(x => t - x < 2.5);
        list.push(t);
        if (list.length >= 3 && t - (this.lastPet.get(id) ?? -Infinity) > 3) {
          this.lastPet.set(id, t); list = [];
          this.onPet && this.onPet(id);
        }
        this.pets.set(id, list);
      }
      return;
    }
    if (speed < 400) return;

    // sweep: fast pass over several critters
    this.sweepTrail = this.sweepTrail.filter(x => t - x.t < 0.5);
    this.sweepTrail.push({ t, p });
    if (speed >= 700 && t >= this.sweepCooldownUntil) {
      for (const [id, r] of this.targets) {
        if (this.sweepHits.includes(id)) continue;
        if (segmentHitsRect(last.p, p, r)) this.sweepHits.push(id);
      }
    }
    if (this.sweepHits.length >= 2 && (this.sweepTrail.length && t - this.sweepTrail[0].t > 0.25)) {
      const ids = this.sweepHits; this.sweepHits = []; this.sweepCooldownUntil = t + 1.5;
      for (const id of ids) { this.lastSwing.set(id, t); this.passes.delete(id); }
      this.onSweep && this.onSweep(ids);
      return;
    }

    for (const [id, r] of this.targets) {
      const midX = r.x + r.w / 2, midY = r.y + r.h / 2;
      const mY = (p.y + last.p.y) / 2, mX = (p.x + last.p.x) / 2;
      const ax = last.p.x - midX, bx = p.x - midX, ay = last.p.y - midY, by = p.y - midY;
      const crossX = mY >= r.y - 14 && mY <= r.y + r.h + 14 && ((ax < 0 && bx >= 0) || (ax > 0 && bx <= 0));
      const crossY = mX >= r.x - 14 && mX <= r.x + r.w + 14 && ((ay < 0 && by >= 0) || (ay > 0 && by <= 0));
      if (!crossX && !crossY) continue;
      const entered = this.enteredAt.get(id);
      if (entered === undefined || t - entered < 0.25) continue;
      let list = (this.passes.get(id) || []).filter(x => t - x < 0.8);
      list.push(t);
      if (list.length >= 2 && t - (this.lastSwing.get(id) ?? -Infinity) > 1.5) {
        this.lastSwing.set(id, t); list = [];
        this.sweepHits = [];
        this.onSwing && this.onSwing(id);
      }
      this.passes.set(id, list);
    }
  }
}

function segmentHitsRect(a, b, r) {
  const steps = 6;
  for (let i = 0; i <= steps; i++) {
    const x = a.x + (b.x - a.x) * i / steps, y = a.y + (b.y - a.y) * i / steps;
    if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) return true;
  }
  return false;
}

module.exports = { SwingDetector };
