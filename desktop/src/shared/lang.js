// Language: English is the source text; Korean and Japanese come from lang.json, which tools/extract-lang.js
// generates from the macOS app's Sources/Lang.swift so both apps share one translation table.
const table = require('./lang.json');

let current = 'en';
const LANGS = { en: 'English', ko: '한국어', ja: '日本語' };

function setLang(l) { if (LANGS[l]) current = l; }
function getLang() { return current; }

/** t("English") → translated string, or English when no translation exists */
function t(en) {
  if (current === 'en') return en;
  const row = table[en];
  if (!row) return en;
  return current === 'ko' ? row[0] : row[1];
}

/** tf("%d critters", 3) — %d %s %@ %.1f %f like String(format:) */
function tf(en, ...args) {
  let i = 0;
  return t(en).replace(/%(\.\d+)?([dsf@])/g, (m, prec, k) => {
    const v = args[i++];
    if (k === 'd') return String(Math.trunc(Number(v)));
    if (k === 'f') return Number(v).toFixed(prec ? Number(prec.slice(1)) : 6);
    return String(v);
  });
}

module.exports = { t, tf, setLang, getLang, LANGS };
