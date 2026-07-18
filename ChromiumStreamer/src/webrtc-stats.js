'use strict';

function values(report) {
  if (!report) return [];
  const result = [];
  report.forEach((entry) => result.push(entry));
  return result;
}

function delta(current, previous, key) {
  if (!previous || !Number.isFinite(current?.[key]) || !Number.isFinite(previous?.[key])) return undefined;
  const value = current[key] - previous[key];
  return value >= 0 ? value : undefined;
}

function rate(bytes, elapsedSeconds) {
  return Number.isFinite(bytes) && elapsedSeconds > 0 ? bytes * 8 / elapsedSeconds : undefined;
}

class StatsSampler {
  constructor(direction) { this.direction = direction; this.previous = undefined; }
  sample(report) {
    const entries = values(report);
    const primaryType = this.direction === 'outbound' ? 'outbound-rtp' : 'inbound-rtp';
    const primary = entries.find((entry) => entry.type === primaryType && (entry.kind === 'video' || entry.mediaType === 'video'));
    if (!primary) return null;
    const previous = this.previous?.primary;
    const elapsed = previous ? (primary.timestamp - previous.timestamp) / 1000 : 0;
    const bytesKey = this.direction === 'outbound' ? 'bytesSent' : 'bytesReceived';
    const framesKey = this.direction === 'outbound' ? 'framesEncoded' : 'framesDecoded';
    const bytesDelta = delta(primary, previous, bytesKey);
    const framesDelta = delta(primary, previous, framesKey);
    const remote = entries.find((entry) => entry.type === 'remote-inbound-rtp' && (entry.kind === 'video' || entry.mediaType === 'video'));
    const previousRemote = this.previous?.remote;
    const lostDelta = delta(this.direction === 'outbound' ? remote : primary, this.direction === 'outbound' ? previousRemote : previous, 'packetsLost');
    const receivedDelta = delta(this.direction === 'outbound' ? remote : primary, this.direction === 'outbound' ? previousRemote : previous, 'packetsReceived');
    const totalPackets = (lostDelta || 0) + (receivedDelta || 0);
    const emittedDelta = delta(primary, previous, 'jitterBufferEmittedCount');
    const delayDelta = delta(primary, previous, 'jitterBufferDelay');
    const encodeDelta = delta(primary, previous, 'totalEncodeTime');
    const qpDelta = delta(primary, previous, 'qpSum');
    const codec = entries.find((entry) => entry.id === primary.codecId && entry.type === 'codec');
    const sample = {
      timestamp: primary.timestamp,
      bitrateBps: rate(bytesDelta, elapsed),
      framesPerSecond: primary.framesPerSecond,
      framesDelta,
      averageEncodeTimeMs: framesDelta > 0 && encodeDelta !== undefined ? encodeDelta / framesDelta * 1000 : undefined,
      averageQp: framesDelta > 0 && qpDelta !== undefined ? qpDelta / framesDelta : undefined,
      playoutDelayMs: emittedDelta > 0 && delayDelta !== undefined ? delayDelta / emittedDelta * 1000 : undefined,
      jitterSeconds: primary.jitter,
      packetLossRate: totalPackets > 0 ? (lostDelta || 0) / totalPackets : undefined,
      roundTripTimeMs: Number.isFinite(remote?.roundTripTime) ? remote.roundTripTime * 1000 : undefined,
      qualityLimitationReason: primary.qualityLimitationReason,
      framesDroppedDelta: delta(primary, previous, 'framesDropped'),
      freezeCountDelta: delta(primary, previous, 'freezeCount'),
      width: primary.frameWidth,
      height: primary.frameHeight,
      codecMimeType: typeof codec?.mimeType === 'string' ? codec.mimeType : undefined,
    };
    this.previous = { primary: { ...primary }, remote: remote ? { ...remote } : undefined };
    return sample;
  }
  reset() { this.previous = undefined; }
}

module.exports = { StatsSampler };
