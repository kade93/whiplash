// Bridge between the pages and the main process. Pages get the sprite table, the translation table and a tiny IPC API.
const { contextBridge, ipcRenderer } = require('electron');
const sprites = require('../shared/sprites.json');
const lang = require('../shared/lang.json');

contextBridge.exposeInMainWorld('SPRITES', sprites);
contextBridge.exposeInMainWorld('LANG_TABLE', lang);
contextBridge.exposeInMainWorld('whiplash', {
  on: (channel, fn) => { ipcRenderer.on(channel, (_e, ...args) => fn(...args)); },
  send: (channel, ...args) => ipcRenderer.send(channel, ...args),
  invoke: (channel, ...args) => ipcRenderer.invoke(channel, ...args),
  platform: process.platform,
});
