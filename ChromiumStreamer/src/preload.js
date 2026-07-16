'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('streamHost', {
  ready: () => ipcRenderer.send('host-ready'),
  signal: (message) => ipcRenderer.send('host-signal', message),
  onViewerConnected: (handler) => ipcRenderer.on('viewer-connected', (_event, id) => handler(id)),
  onViewerDisconnected: (handler) => ipcRenderer.on('viewer-disconnected', (_event, id) => handler(id)),
  onViewerSignal: (handler) => ipcRenderer.on('viewer-signal', (_event, value) => handler(value))
});
