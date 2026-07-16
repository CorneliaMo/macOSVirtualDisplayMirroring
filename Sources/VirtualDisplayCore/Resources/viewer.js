(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const video = $('video'), status = $('connection');
  const statIds = ['resolution','fps','bitrate','codec','jitter','decode','buffer','lost','dropped'];
  let socket, peer, timer, lastBytes = 0, lastAt = 0, remoteReady = false, candidates = [];

  function label(text, live = false) { status.textContent = text; status.classList.toggle('live', live); }
  function resetStats() { statIds.forEach(id => { const el = $(id); if (el) el.textContent = '—'; }); lastBytes = 0; lastAt = 0; }
  function averageMs(total, count) { return Number.isFinite(total) && count > 0 ? `${(total * 1000 / count).toFixed(1)} ms` : '—'; }
  function send(value) { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value)); }
  async function flushCandidates() { for (const c of candidates) await peer.addIceCandidate(c); candidates = []; }
  function disconnect() {
    clearInterval(timer); timer = undefined; remoteReady = false; candidates = [];
    peer?.close(); peer = undefined; socket?.close(); socket = undefined;
    video.srcObject = null; video.classList.remove('live'); resetStats(); label('DISCONNECTED');
  }
  function connect() {
    disconnect(); label('CONNECTING');
    const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(`${scheme}://${location.host}/signal`); socket = ws;
    ws.onmessage = async event => {
      if (socket !== ws) return;
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'offer') {
          peer = new RTCPeerConnection({iceServers: []});
          peer.ontrack = e => { video.srcObject = e.streams[0]; video.classList.add('live'); label('LIVE', true); startStats(); };
          peer.onicecandidate = e => { if (e.candidate) send({type:'candidate',candidate:e.candidate.candidate,sdpMid:e.candidate.sdpMid,sdpMLineIndex:e.candidate.sdpMLineIndex}); };
          peer.onconnectionstatechange = () => { if (['failed','closed','disconnected'].includes(peer.connectionState)) label(peer.connectionState.toUpperCase()); };
          await peer.setRemoteDescription({type:'offer',sdp:msg.sdp}); remoteReady = true; await flushCandidates();
          const answer = await peer.createAnswer(); await peer.setLocalDescription(answer); send({type:'answer',sdp:answer.sdp});
        } else if (msg.type === 'candidate') {
          const candidate = {candidate:msg.candidate,sdpMid:msg.sdpMid,sdpMLineIndex:msg.sdpMLineIndex};
          if (remoteReady) await peer.addIceCandidate(candidate); else candidates.push(candidate);
        } else if (msg.type === 'error') { label(`ERROR: ${msg.message || 'UNKNOWN'}`); }
      } catch (error) { label('SIGNAL ERROR'); console.error(error); }
    };
    ws.onerror = () => { if (socket === ws) label('SIGNAL ERROR'); };
    ws.onclose = () => { if (socket === ws && !peer) label('DISCONNECTED'); };
  }
  function startStats() {
    clearInterval(timer); resetStats();
    timer = setInterval(async () => {
      if (!peer) return;
      const reports = await peer.getStats();
      const codecs = new Map();
      reports.forEach(r => { if (r.type === 'codec') codecs.set(r.id, r); });
      reports.forEach(r => {
        if (r.type !== 'inbound-rtp' || r.kind !== 'video') return;
        $('resolution').textContent = r.frameWidth ? `${r.frameWidth} × ${r.frameHeight}` : '—';
        $('fps').textContent = r.framesPerSecond == null ? '—' : `${Math.round(r.framesPerSecond)} FPS`;
        const dt = r.timestamp - lastAt, bytes = r.bytesReceived - lastBytes;
        $('bitrate').textContent = lastAt && dt > 0 && bytes >= 0 ? `${(bytes * 8 / dt / 1000).toFixed(2)} Mbps` : '—';
        const codec = codecs.get(r.codecId);
        $('codec').textContent = codec?.mimeType?.replace(/^video\//i, '') || '—';
        $('jitter').textContent = r.jitter == null ? '—' : `${(r.jitter * 1000).toFixed(1)} ms`;
        $('decode').textContent = averageMs(r.totalDecodeTime, r.framesDecoded);
        $('buffer').textContent = averageMs(r.jitterBufferDelay, r.jitterBufferEmittedCount);
        $('lost').textContent = String(r.packetsLost ?? '—');
        $('dropped').textContent = String(r.framesDropped ?? '—');
        lastBytes = r.bytesReceived; lastAt = r.timestamp;
      });
    }, 1000);
  }
  function fullscreen() { (document.fullscreenElement ? document.exitFullscreen() : video.requestFullscreen()).catch?.(() => {}); }
  $('fullscreen').addEventListener('click', fullscreen); $('reconnect').addEventListener('click', connect);
  document.addEventListener('keydown', e => { if (e.key.toLowerCase() === 'f' && !/input|textarea/i.test(e.target.tagName)) fullscreen(); });
  addEventListener('beforeunload', disconnect); connect();
})();
