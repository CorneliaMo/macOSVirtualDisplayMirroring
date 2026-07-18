import { AdaptiveQualityController } from './adaptive-quality-controller.js';
import { MotionSampler } from './motion-sampler.js';
import { decodeMessage, encodeMessage } from './protocol.js';
import { profileSettings } from './quality-profiles.js';
import { setVideoBandwidth } from './sdp.js';
import { StatsSampler } from './webrtc-stats.js';

const video = document.querySelector('#video'); const canvas = document.querySelector('#sample'); const state = document.querySelector('#state');
const ids = ['codec', 'fps', 'rate', 'buffer', 'profile', 'rtt', 'loss', 'qp', 'limitation', 'resolution', 'decision'];
const fields = Object.fromEntries(ids.map((id) => [id, document.querySelector(`#${id}`)]));
const baseBitrateBps = window.streamConfiguration?.bitrate || 500_000_000; const baseFps = window.streamConfiguration?.fps || 60;
let socket; let peer; let quality = '1'; let hostSample; let receiverSample; let motionRatio = 0; let sequence = 0;
let receiverStatsPending = false;
const history = []; const sampler = new StatsSampler('inbound'); const motionSampler = new MotionSampler(video, canvas);
const controller = new AdaptiveQualityController({ baseBitrateBps, baseFps });

function setState(value) { state.textContent = value; }
function send(value) { if (peer?.connected) peer.send(typeof value === 'string' ? value : encodeMessage(value)); }
function requestManualQuality(scale) { send(JSON.stringify({ type: 'quality', scale })); }
function record(sample) {
  history.push(sample); const cutoff = Date.now() - 60_000;
  while (history.length && (history.length > 120 || Date.parse(history[0].at) < cutoff)) history.shift();
}
function requestProfile(profile, reason, resolvedSettings) {
  const settings = resolvedSettings || profileSettings(profile, baseBitrateBps, baseFps); sequence += 1;
  send({ type: 'quality-command', sequence, ...settings }); fields.decision.textContent = reason; fields.profile.textContent = profile.toUpperCase();
  record({ at: new Date().toISOString(), type: 'decision', reason, ...settings });
}
function onData(bytes) {
  const message = decodeMessage(bytes); if (!message) return;
  if (message.type === 'host-stats') hostSample = message.sample;
  if (message.type === 'quality-applied') record({ at: new Date().toISOString(), ...message });
}
function connect() {
  peer?.destroy(); socket?.disconnect(); sampler.reset(); controller.reset(); hostSample = undefined; receiverSample = undefined; setState('CONNECTING');
  socket = window.io({ transports: ['websocket'] });
  peer = new window.SimplePeer({ initiator: false, trickle: true, config: { iceServers: [] }, sdpTransform: (sdp) => setVideoBandwidth(sdp, baseBitrateBps) });
  peer.on('signal', (signal) => socket.emit('signal', signal)); socket.on('signal', (signal) => peer.signal(signal)); peer.on('data', onData);
  peer.on('stream', (stream) => { video.srcObject = stream; video.play().catch(() => {}); setState('LIVE'); });
  peer.on('connect', () => quality === 'auto' ? requestProfile('detail', 'auto-start') : requestManualQuality(Number(quality)));
  peer.on('close', () => setState('DISCONNECTED')); peer.on('error', () => setState('CONNECTION ERROR')); socket.on('disconnect', () => setState('DISCONNECTED'));
}

document.querySelectorAll('[data-quality]').forEach((button) => button.addEventListener('click', () => {
  document.querySelectorAll('[data-quality]').forEach((item) => item.classList.toggle('active', item === button));
  quality = button.dataset.quality; controller.reset(); motionSampler.reset();
  if (quality === 'auto') { requestManualQuality(1); requestProfile('detail', 'auto-enabled'); } else { requestManualQuality(Number(quality)); fields.profile.textContent = `${Number(quality) * 100}%`; fields.decision.textContent = 'manual'; }
}));
document.querySelector('#reconnect').addEventListener('click', connect);
document.querySelector('#fullscreen').addEventListener('click', () => (document.fullscreenElement ? document.exitFullscreen() : video.requestFullscreen()).catch(() => {}));
document.querySelector('#copy-stats').addEventListener('click', async () => { try { await navigator.clipboard.writeText(JSON.stringify(history, null, 2)); fields.decision.textContent = 'stats copied'; } catch { fields.decision.textContent = 'copy failed'; } });

setInterval(() => { if (quality !== 'auto') return; const value = motionSampler.sample(); if (value !== undefined) motionRatio = value; }, 1000);
setInterval(async () => {
  if (!peer?._pc || receiverStatsPending) return;
  receiverStatsPending = true;
  try {
  const connection = peer._pc; const reports = await connection.getStats();
  if (peer?._pc !== connection) return;
  receiverSample = sampler.sample(reports); if (!receiverSample) return;
  fields.codec.textContent = receiverSample.codecMimeType?.split('/')[1] || '—';
  fields.fps.textContent = Math.round(receiverSample.framesPerSecond || 0); fields.rate.textContent = receiverSample.bitrateBps ? `${(receiverSample.bitrateBps / 1e6).toFixed(1)} Mbps` : '—';
  fields.buffer.textContent = receiverSample.playoutDelayMs === undefined ? '—' : `${receiverSample.playoutDelayMs.toFixed(0)} ms`;
  fields.rtt.textContent = hostSample?.roundTripTimeMs === undefined ? '—' : `${hostSample.roundTripTimeMs.toFixed(0)} ms`;
  const loss = Math.max(receiverSample.packetLossRate ?? 0, hostSample?.packetLossRate ?? 0); fields.loss.textContent = `${(loss * 100).toFixed(1)}%`;
  fields.qp.textContent = hostSample?.averageQp === undefined ? '—' : hostSample.averageQp.toFixed(1); fields.limitation.textContent = hostSample?.qualityLimitationReason || '—';
  fields.resolution.textContent = `${video.videoWidth || 0}×${video.videoHeight || 0}`;
  const snapshot = { at: new Date().toISOString(), type: 'stats', motionRatio, receiver: receiverSample, host: hostSample }; record(snapshot);
  if (quality === 'auto') { const decision = controller.observe(snapshot, performance.now()); if (decision) requestProfile(decision.profile, decision.reason, decision.settings); }
  } catch (error) { console.error('WebRTC receiver stats failed', error); }
  finally { receiverStatsPending = false; }
}, 500);

connect();
