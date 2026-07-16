'use strict';

const { app, BrowserWindow, desktopCapturer, ipcMain } = require('electron');
const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const { parseArgs } = require('./args');

let options;
let hostWindow;
let activeViewer;
let hostReady = false;

function sendToHost(channel, value) {
  if (hostReady && hostWindow && !hostWindow.isDestroyed()) hostWindow.webContents.send(channel, value);
}

function matchesDisplay(source, displayId) {
  if (String(source.display_id) === String(displayId)) return true;
  const sourceDisplayId = String(source.id).split(':')[1];
  return sourceDisplayId === String(displayId);
}

async function createHost() {
  const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } });
  const source = sources.find((candidate) => matchesDisplay(candidate, options.displayId));
  if (!source) throw new Error(`Chromium could not locate display ${options.displayId}`);
  hostWindow = new BrowserWindow({
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'), contextIsolation: true,
      nodeIntegration: false, sandbox: true, backgroundThrottling: false
    }
  });
  await hostWindow.loadFile(path.join(__dirname, 'host.html'), { query: {
    sourceId: source.id, width: String(options.width), height: String(options.height), fps: String(options.fps)
  }});
}

function startServer() {
  const web = express();
  const server = http.createServer(web);
  const io = new Server(server, { serveClient: true });
  web.use((_request, response, next) => { response.setHeader('Cache-Control', 'no-store'); next(); });
  web.get('/healthz', (_request, response) => response.json({
    backend: 'chromium', displayID: Number(options.displayId), width: options.width, height: options.height,
    fps: options.fps, viewerConnected: Boolean(activeViewer && activeViewer.connected), hostReady
  }));
  web.use(express.static(path.join(__dirname, '..', 'public')));
  web.get('/vendor/simplepeer.min.js', (_request, response) => {
    response.sendFile(path.join(__dirname, '..', 'node_modules', 'simple-peer', 'simplepeer.min.js'));
  });
  web.use('/dist', express.static(path.join(__dirname, '..', 'dist')));
  io.on('connection', (socket) => {
    if (activeViewer && activeViewer.id !== socket.id) activeViewer.disconnect(true);
    activeViewer = socket;
    sendToHost('viewer-connected', socket.id);
    socket.on('signal', (signal) => sendToHost('viewer-signal', { viewerId: socket.id, signal }));
    socket.on('disconnect', () => {
      if (activeViewer?.id === socket.id) { activeViewer = undefined; sendToHost('viewer-disconnected', socket.id); }
    });
  });
  ipcMain.on('host-ready', (event) => {
    if (event.sender !== hostWindow?.webContents) return;
    hostReady = true;
    if (activeViewer?.connected) sendToHost('viewer-connected', activeViewer.id);
  });
  ipcMain.on('host-signal', (event, message) => {
    if (event.sender !== hostWindow?.webContents) return;
    if (activeViewer?.id === message.viewerId) activeViewer.emit('signal', message.signal);
  });
  server.on('error', (error) => { console.error('HTTP server failed', error); app.exit(1); });
  server.listen(options.port, '0.0.0.0', () => console.log(`Chromium viewer: http://127.0.0.1:${options.port}/`));
}

app.whenReady().then(async () => {
  options = parseArgs(process.argv.slice(2));
  startServer();
  await createHost();
}).catch((error) => { console.error(error); app.exit(1); });

app.on('window-all-closed', () => {});
