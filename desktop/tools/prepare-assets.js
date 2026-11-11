#!/usr/bin/env node
// Copies the shared resources from the repository root into desktop/assets (git-ignored):
//   ../Resources/*.wav          → assets/sounds/      whip and angry sounds
//   ../AppIcon.iconset/*.png     → assets/icon/        app + tray icons
// and refreshes the generated sprite/translation tables. Runs before `npm start` and every build.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const root = path.join(__dirname, '..', '..');
const assets = path.join(__dirname, '..', 'assets');
fs.mkdirSync(path.join(assets, 'sounds'), { recursive: true });
fs.mkdirSync(path.join(assets, 'icon'), { recursive: true });
for (const f of fs.readdirSync(path.join(root, 'Resources'))) {
  if (f.endsWith('.wav')) fs.copyFileSync(path.join(root, 'Resources', f), path.join(assets, 'sounds', f));
}
const iconset = path.join(root, 'AppIcon.iconset');
const pick = { 'icon_512x512@2x.png': 'icon.png', 'icon_256x256.png': 'icon-256.png', 'icon_32x32.png': 'tray.png', 'icon_32x32@2x.png': 'tray@2x.png', 'icon_16x16.png': 'tray-16.png' };
for (const [from, to] of Object.entries(pick)) fs.copyFileSync(path.join(iconset, from), path.join(assets, 'icon', to));
// electron-builder reads its icon from the buildResources folder
fs.mkdirSync(path.join(__dirname, '..', 'resources'), { recursive: true });
fs.copyFileSync(path.join(iconset, 'icon_512x512@2x.png'), path.join(__dirname, '..', 'resources', 'icon.png'));
execFileSync(process.execPath, [path.join(__dirname, 'extract-sprites.js')], { stdio: 'inherit' });
execFileSync(process.execPath, [path.join(__dirname, 'extract-lang.js')], { stdio: 'inherit' });
console.log('assets ready');
