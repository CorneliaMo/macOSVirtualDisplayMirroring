import { decodeMessage, encodeMessage } from './protocol.js';
import { StatsSampler } from './webrtc-stats.js';

const query = new URLSearchParams(location.search);
const sourceId = query.get('sourceId');
const width = Number(query.get('width'));
const height = Number(query.get('height'));
const fps = Number(query.get('fps'));
const bitrate = Number(query.get('bitrate'));
let peer;
let stream;
let viewerId;
let qualityChange = Promise.resolve();
let statsTimer;
let statsPending = false;
let lastQualitySequence = -1;
let captureScale = 1;
const statsSampler = new StatsSampler('outbound');

async function capture(scale = 1) {
  return navigator.mediaDevices.getUserMedia({ audio: false, video: { mandatory: {
    chromeMediaSource: 'desktop', chromeMediaSourceId: sourceId,
    minWidth: Math.max(2, Math.round(width * scale)), maxWidth: Math.max(2, Math.round(width * scale)),
    minHeight: Math.max(2, Math.round(height * scale)), maxHeight: Math.max(2, Math.round(height * scale)),
    minFrameRate: 15, maxFrameRate: fps
  } } });
}

async function replaceQuality(scale) {
  if (stream && scale === captureScale) return;
  const replacement = await capture(scale === 0.5 ? 0.5 : 1);
  const oldTrack = stream?.getVideoTracks()[0]; const nextTrack = replacement.getVideoTracks()[0];
  if (!stream || !oldTrack) { stream = replacement; captureScale = scale; return; }
  if (peer) peer.replaceTrack(oldTrack, nextTrack, stream);
  stream.removeTrack(oldTrack); stream.addTrack(nextTrack); oldTrack.stop(); captureScale = scale;
}

function videoSender() { return peer?._pc?.getSenders().find((sender) => sender.track?.kind === 'video'); }

async function applyProfile(message) {
  const sender = videoSender(); if (!sender) throw new Error('Video sender is unavailable');
  const parameters = sender.getParameters();
  if (!parameters.encodings?.length) parameters.encodings = [{}];
  parameters.encodings[0].maxBitrate = message.maxBitrateBps;
  parameters.encodings[0].maxFramerate = message.maxFps;
  await sender.setParameters(parameters);
  const settings = sender.track?.getSettings() || {}; const applied = sender.getParameters().encodings?.[0] || {};
  peer.send(encodeMessage({ type: 'quality-applied', sequence: message.sequence, profile: message.profile,
    trackWidth: settings.width || width, trackHeight: settings.height || height,
    maxFps: applied.maxFramerate || message.maxFps, maxBitrateBps: applied.maxBitrate || message.maxBitrateBps }));
}

async function applyManual(scale) {
  await replaceQuality(scale);
  const sender = videoSender(); if (!sender) return;
  const parameters = sender.getParameters();
  if (!parameters.encodings?.length) parameters.encodings = [{}];
  parameters.encodings[0].maxBitrate = bitrate;
  parameters.encodings[0].maxFramerate = fps;
  await sender.setParameters(parameters);
}

async function sendStats() {
  if (!peer?.connected || !peer._pc || statsPending) return;
  statsPending = true;
  try {
    const connection = peer._pc; const reports = await connection.getStats();
    if (peer?._pc !== connection) return;
    const sample = statsSampler.sample(reports);
    if (sample && peer.connected) peer.send(encodeMessage({ type: 'host-stats', sample }));
  } finally { statsPending = false; }
}

async function rebuild(id) {
  peer?.destroy(); clearInterval(statsTimer); statsPending = false; statsSampler.reset(); lastQualitySequence = -1; viewerId = id;
  if (!stream) stream = await capture(1);
  const candidate = new window.SimplePeer({ initiator: true, trickle: true, stream, config: { iceServers: [] } });
  peer = candidate;
  candidate.on('signal', (signal) => window.streamHost.signal({ viewerId: id, signal }));
  candidate.on('connect', () => { statsTimer = setInterval(() => sendStats().catch(console.error), 500); });
  candidate.on('data', (bytes) => {
    const legacy = (() => { try { return JSON.parse(new TextDecoder().decode(bytes)); } catch { return null; } })();
    if (legacy?.type === 'quality' && [0.5, 1].includes(legacy.scale)) qualityChange = qualityChange.then(() => applyManual(legacy.scale)).catch(console.error);
    const message = decodeMessage(bytes);
    if (message?.type === 'quality-command' && message.sequence > lastQualitySequence) {
      lastQualitySequence = message.sequence;
      qualityChange = qualityChange.then(() => applyProfile(message)).catch(console.error);
    }
  });
  candidate.on('error', (error) => console.error('WebRTC host error', error));
}

window.streamHost.onViewerConnected((id) => rebuild(id).catch(console.error));
window.streamHost.onViewerDisconnected((id) => { if (id === viewerId) { clearInterval(statsTimer); peer?.destroy(); peer = undefined; } });
window.streamHost.onViewerSignal(({ viewerId: id, signal }) => { if (id === viewerId) peer?.signal(signal); });
window.streamHost.ready();
