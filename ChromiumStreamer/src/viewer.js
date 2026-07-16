import pixelmatch from 'pixelmatch';
import { QualityPolicy } from './quality-policy.js';
import { setVideoBandwidth } from './sdp.js';

const video = document.querySelector('#video');
const canvas = document.querySelector('#sample');
const state = document.querySelector('#state');
const fields = Object.fromEntries(['codec', 'fps', 'rate', 'buffer'].map((id) => [id, document.querySelector(`#${id}`)]));
let socket;
let peer;
let quality = '1';
let previousPixels;
let statsPrevious;
const policy = new QualityPolicy();

function setState(value) { state.textContent = value; }
function requestQuality(scale) { if (peer?.connected) peer.send(JSON.stringify({ type: 'quality', scale })); }
function connect() {
  peer?.destroy(); socket?.disconnect(); setState('CONNECTING');
  socket = window.io({ transports: ['websocket'] });
  peer = new window.SimplePeer({
    initiator: false,
    trickle: true,
    config: { iceServers: [] },
    sdpTransform: (sdp) => setVideoBandwidth(sdp, 500_000),
  });
  peer.on('signal', (signal) => socket.emit('signal', signal));
  socket.on('signal', (signal) => peer.signal(signal));
  peer.on('stream', (stream) => { video.srcObject = stream; video.play().catch(() => {}); setState('LIVE'); });
  peer.on('connect', () => requestQuality(quality === 'auto' ? 1 : Number(quality)));
  peer.on('close', () => setState('DISCONNECTED'));
  peer.on('error', () => setState('CONNECTION ERROR'));
  socket.on('disconnect', () => setState('DISCONNECTED'));
}

document.querySelectorAll('[data-quality]').forEach((button) => button.addEventListener('click', () => {
  document.querySelectorAll('[data-quality]').forEach((item) => item.classList.toggle('active', item === button));
  quality = button.dataset.quality; policy.reset(); previousPixels = undefined;
  requestQuality(quality === 'auto' ? 1 : Number(quality));
}));
document.querySelector('#reconnect').addEventListener('click', connect);
document.querySelector('#fullscreen').addEventListener('click', () => (document.fullscreenElement ? document.exitFullscreen() : video.requestFullscreen()).catch(() => {}));

setInterval(() => {
  if (quality !== 'auto' || video.readyState < 2 || !video.videoWidth) return;
  const width = Math.max(1, Math.floor(video.videoWidth / 8)); const height = Math.max(1, Math.floor(video.videoHeight / 8));
  canvas.width = width; canvas.height = height; const context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(video, 0, 0, width, height); const current = context.getImageData(0, 0, width, height);
  if (previousPixels) { const changed = pixelmatch(previousPixels.data, current.data, null, width, height, { threshold: 0.1 }); const scale = policy.observe(changed / (width * height)); if (scale) requestQuality(scale); }
  previousPixels = current;
}, 1000);

setInterval(async () => {
  if (!peer?._pc) return;
  const reports = await peer._pc.getStats(); let inbound; let codec;
  reports.forEach((report) => { if (report.type === 'inbound-rtp' && report.kind === 'video') inbound = report; });
  if (!inbound) return;
  reports.forEach((report) => { if (report.id === inbound.codecId) codec = report; });
  const elapsed = statsPrevious ? (inbound.timestamp - statsPrevious.timestamp) / 1000 : 0;
  fields.codec.textContent = codec?.mimeType?.split('/')[1] || '—'; fields.fps.textContent = Math.round(inbound.framesPerSecond || 0);
  fields.rate.textContent = elapsed > 0 ? `${(((inbound.bytesReceived - statsPrevious.bytesReceived) * 8 / elapsed) / 1e6).toFixed(1)} Mbps` : '—';
  const emitted = statsPrevious ? inbound.jitterBufferEmittedCount - statsPrevious.emitted : 0;
  fields.buffer.textContent = emitted > 0 ? `${((inbound.jitterBufferDelay - statsPrevious.delay) / emitted * 1000).toFixed(0)} ms` : '—';
  statsPrevious = { timestamp: inbound.timestamp, bytesReceived: inbound.bytesReceived, emitted: inbound.jitterBufferEmittedCount, delay: inbound.jitterBufferDelay };
}, 1000);

connect();
