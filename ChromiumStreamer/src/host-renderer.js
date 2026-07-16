const query = new URLSearchParams(location.search);
const sourceId = query.get('sourceId');
const width = Number(query.get('width'));
const height = Number(query.get('height'));
const fps = Number(query.get('fps'));
let peer;
let stream;
let viewerId;
let qualityChange = Promise.resolve();

async function capture(scale = 1) {
  return navigator.mediaDevices.getUserMedia({ audio: false, video: { mandatory: {
    chromeMediaSource: 'desktop', chromeMediaSourceId: sourceId,
    minWidth: Math.max(2, Math.round(width * scale)), maxWidth: Math.max(2, Math.round(width * scale)),
    minHeight: Math.max(2, Math.round(height * scale)), maxHeight: Math.max(2, Math.round(height * scale)),
    minFrameRate: 15, maxFrameRate: fps
  } } });
}

async function replaceQuality(scale) {
  const replacement = await capture(scale === 0.5 ? 0.5 : 1);
  const oldTrack = stream?.getVideoTracks()[0];
  const nextTrack = replacement.getVideoTracks()[0];
  if (!stream || !oldTrack) { stream = replacement; return; }
  if (peer) peer.replaceTrack(oldTrack, nextTrack, stream);
  stream.removeTrack(oldTrack); stream.addTrack(nextTrack); oldTrack.stop();
}

async function rebuild(id) {
  peer?.destroy();
  viewerId = id;
  if (!stream) stream = await capture(1);
  const candidate = new window.SimplePeer({ initiator: true, trickle: true, stream, config: { iceServers: [] } });
  peer = candidate;
  candidate.on('signal', (signal) => window.streamHost.signal({ viewerId: id, signal }));
  candidate.on('data', (bytes) => {
    try {
      const message = JSON.parse(new TextDecoder().decode(bytes));
      if (message.type === 'quality') qualityChange = qualityChange.then(() => replaceQuality(message.scale)).catch(console.error);
    } catch {}
  });
  candidate.on('error', (error) => console.error('WebRTC host error', error));
}

window.streamHost.onViewerConnected((id) => rebuild(id).catch(console.error));
window.streamHost.onViewerDisconnected((id) => { if (id === viewerId) { peer?.destroy(); peer = undefined; } });
window.streamHost.onViewerSignal(({ viewerId: id, signal }) => { if (id === viewerId) peer?.signal(signal); });
window.streamHost.ready();
