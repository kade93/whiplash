#!/usr/bin/env node
// Pulls the English → (Korean, Japanese) table out of ../Sources/Lang.swift so the two apps share one set of translations.
// Run after editing Lang.swift:  node tools/extract-lang.js  → src/shared/lang.json
// Lines it can't parse (multi-line entries) are skipped; English is used for those.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', '..', 'Sources', 'Lang.swift'), 'utf8');
const table = {};
// Swift string literal: "..." with \" and \\ escapes and \n
const lit = '"((?:[^"\\\\]|\\\\.)*)"';
const re = new RegExp(`^\\s*${lit}:\\s*\\(${lit},\\s*${lit}\\),?\\s*(?://.*)?$`, 'gm');
const unesc = s => s.replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
for (const m of src.matchAll(re)) table[unesc(m[1])] = [unesc(m[2]), unesc(m[3])];
const dest = path.join(__dirname, '..', 'src', 'shared', 'lang.json');
fs.writeFileSync(dest, JSON.stringify(table, null, 0).replace(/\],"/g, '],\n"') + '\n');
console.log(`lang.json: ${Object.keys(table).length} strings → ${path.relative(process.cwd(), dest)}`);
