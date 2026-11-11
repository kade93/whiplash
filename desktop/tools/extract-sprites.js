#!/usr/bin/env node
// Pulls the pixel data out of ../Sources/Sprites.swift (the macOS app) so both apps draw the same critters.
// Run after editing Sprites.swift:  node tools/extract-sprites.js  → src/shared/sprites.json
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', '..', 'Sources', 'Sprites.swift'), 'utf8');

function hex(s) { return '#' + s.padStart(6, '0'); }
function rowsOf(block) { return [...block.matchAll(/"([.KEBLACWMPYRGOD]+)"/g)].map(m => m[1]); }

// Sprites: `static let NAME = Sprite(friend: "...", rows: [...] or crabRows, body: Color(hex: 0x..), light: ..., accent: ..., cheek: ...)`
const crabRowsBlock = src.match(/private static let crabRows = \[([\s\S]*?)\]/)[1];
const crabRows = rowsOf(crabRowsBlock);
const sprites = {};
const spriteRe = /static let (\w+) = Sprite\(friend: "([^"]+)", rows: (crabRows|\[[\s\S]*?\]),\s*body: Color\(hex: 0x([0-9A-F]+)\), light: Color\(hex: 0x([0-9A-F]+)\),\s*accent: Color\(hex: 0x([0-9A-F]+)\), cheek: Color\(hex: 0x([0-9A-F]+)\)\)/g;
for (const m of src.matchAll(spriteRe)) {
  const [, name, friend, rows, body, light, accent, cheek] = m;
  sprites[name] = { friend, rows: rows === 'crabRows' ? crabRows : rowsOf(rows), body: hex(body), light: hex(light), accent: hex(accent), cheek: hex(cheek) };
}

// Tools in hand (ToolArt.rows): `case .read: return [ ... ]`
const tools = {};
const toolBlock = src.slice(src.indexOf('enum ToolArt'), src.indexOf('static let carrot'));
for (const m of toolBlock.matchAll(/case \.(\w+): return \[([\s\S]*?)\]/g)) tools[m[1]] = rowsOf(m[2]);
const chain = rowsOf(src.match(/static let chain = \[([\s\S]*?)\]/)[1]);
const carrot = rowsOf(src.match(/static let carrot = \[([\s\S]*?)\]/)[1]);

// Tool palette (ToolArt.color)
const palette = {};
const palBlock = src.match(/static func color\(_ ch: Character\) -> Color\? \{([\s\S]*?)\n    \}/)[1];
for (const m of palBlock.matchAll(/case "(\w)": return Color\(hex: 0x([0-9A-F]+)\)/g)) palette[m[1]] = hex(m[2]);
palette.K = hex(src.match(/static let ink = Color\(hex: 0x([0-9A-F]+)\)/)[1]);

// Which agent uses which sprite (AgentKind.sprite)
const kinds = {};
for (const m of src.matchAll(/case \.(\w+):\s+return Sprite\.(\w+)/g)) kinds[m[1]] = m[2];
const barColors = {};
for (const m of src.matchAll(/case \.(\w+):\s+return Color\(hex: 0x([0-9A-F]+)\)/g)) barColors[m[1]] = hex(m[2]);

const out = { ink: palette.K, sprites, kinds, barColors, tools, chain, carrot, palette };
const dest = path.join(__dirname, '..', 'src', 'shared', 'sprites.json');
fs.writeFileSync(dest, JSON.stringify(out, null, 1) + '\n');
console.log(`sprites.json: ${Object.keys(sprites).length} sprites, ${Object.keys(tools).length} tools → ${path.relative(process.cwd(), dest)}`);
