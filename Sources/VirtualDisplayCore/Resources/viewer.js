(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const video = $('video'), status = $('connection');
  const statIds = ['resolution','fps','bitrate','codec','jitter','decode','buffer','buffer-target','buffer-minimum','lost','dropped'];
  let socket, peer, timer, remoteReady = false, candidates = [], previousStats = new Map();

  function label(text, live = false) { status.textContent = text; status.classList.toggle('live', live); }
  function resetStats() { statIds.forEach(id => { const el = $(id); if (el) el.textContent = '—'; }); previousStats = new Map(); }
  function averageMs(total, count) { return Number.isFinite(total) && count > 0 ? `${(total * 1000 / count).toFixed(1)} ms` : '—'; }
  function intervalAverageMs(total, count, previous, totalKey) {
    if (!Number.isFinite(total) || !Number.isFinite(count) || !previous) return '—';
    const deltaTotal = total - previous[totalKey], deltaCount = count - previous.jitterBufferEmittedCount;
    return deltaTotal >= 0 && deltaCount > 0 ? `${(deltaTotal * 1000 / deltaCount).toFixed(1)} ms` : '—';
  }
  function videoBandwidth(sdp) {
    const section = sdp.match(/(?:^|\r?\n)m=video[^]*?(?=\r?\nm=|$)/m)?.[0];
    return section?.match(/(?:^|\r?\n)b=AS:(\d+)/m)?.[1];
  }
  function setVideoBandwidth(sdp, bandwidth) {
    if (!bandwidth) return sdp;
    const newline = sdp.includes('\r\n') ? '\r\n' : '\n';
    const lines = sdp.split(newline), media = lines.findIndex(line => line.startsWith('m=video '));
    if (media < 0) return sdp;
    let index = media + 1;
    while (index < lines.length && (lines[index].startsWith('i=') || lines[index].startsWith('c='))) index++;
    if (lines[index]?.startsWith('b=AS:')) lines[index] = `b=AS:${bandwidth}`;
    else lines.splice(index, 0, `b=AS:${bandwidth}`);
    return lines.join(newline);
  }
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
          const answer = await peer.createAnswer();
          const answerSDP = setVideoBandwidth(answer.sdp, videoBandwidth(msg.sdp));
          await peer.setLocalDescription({type:answer.type,sdp:answerSDP}); send({type:'answer',sdp:answerSDP});
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
        const previous = previousStats.get(r.id);
        const dt = previous ? r.timestamp - previous.timestamp : 0;
        const bytes = previous ? r.bytesReceived - previous.bytesReceived : 0;
        $('bitrate').textContent = previous && dt > 0 && bytes >= 0 ? `${(bytes * 8 / dt / 1000).toFixed(2)} Mbps` : '—';
        const codec = codecs.get(r.codecId);
        $('codec').textContent = codec?.mimeType?.replace(/^video\//i, '') || '—';
        $('jitter').textContent = r.jitter == null ? '—' : `${(r.jitter * 1000).toFixed(1)} ms`;
        $('decode').textContent = averageMs(r.totalDecodeTime, r.framesDecoded);
        $('buffer').textContent = intervalAverageMs(r.jitterBufferDelay, r.jitterBufferEmittedCount, previous, 'jitterBufferDelay');
        $('buffer-target').textContent = intervalAverageMs(r.jitterBufferTargetDelay, r.jitterBufferEmittedCount, previous, 'jitterBufferTargetDelay');
        $('buffer-minimum').textContent = intervalAverageMs(r.jitterBufferMinimumDelay, r.jitterBufferEmittedCount, previous, 'jitterBufferMinimumDelay');
        $('lost').textContent = String(r.packetsLost ?? '—');
        $('dropped').textContent = String(r.framesDropped ?? '—');
        previousStats.set(r.id, {
          timestamp: r.timestamp, bytesReceived: r.bytesReceived,
          jitterBufferDelay: r.jitterBufferDelay,
          jitterBufferTargetDelay: r.jitterBufferTargetDelay,
          jitterBufferMinimumDelay: r.jitterBufferMinimumDelay,
          jitterBufferEmittedCount: r.jitterBufferEmittedCount
        });
      });
    }, 1000);
  }
  function fullscreen() { (document.fullscreenElement ? document.exitFullscreen() : video.requestFullscreen()).catch?.(() => {}); }
  $('fullscreen').addEventListener('click', fullscreen); $('reconnect').addEventListener('click', connect);
  document.addEventListener('keydown', e => { if (e.key.toLowerCase() === 'f' && !/input|textarea/i.test(e.target.tagName)) fullscreen(); });
  addEventListener('beforeunload', disconnect); connect();
})();
