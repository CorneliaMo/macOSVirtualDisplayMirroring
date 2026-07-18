'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { StatsSampler } = require('../src/webrtc-stats');
function report(...values) { return new Map(values.map((value) => [value.id, value])); }
test('calculates inbound interval metrics', () => {
  const sampler = new StatsSampler('inbound');
  sampler.sample(report({ id:'v',type:'inbound-rtp',kind:'video',timestamp:1000,bytesReceived:1000,framesDecoded:10,packetsLost:1,packetsReceived:99,jitterBufferDelay:1,jitterBufferEmittedCount:10 }));
  const value = sampler.sample(report({ id:'v',type:'inbound-rtp',kind:'video',timestamp:2000,bytesReceived:3000,framesDecoded:30,packetsLost:2,packetsReceived:198,jitterBufferDelay:3,jitterBufferEmittedCount:30 }));
  assert.equal(value.bitrateBps, 16000); assert.equal(value.playoutDelayMs, 100); assert.equal(value.packetLossRate, .01);
});
test('handles reset counters without negative deltas', () => { const sampler = new StatsSampler('outbound'); sampler.sample(report({id:'v',type:'outbound-rtp',kind:'video',timestamp:1,bytesSent:100,framesEncoded:10})); const value = sampler.sample(report({id:'v',type:'outbound-rtp',kind:'video',timestamp:1001,bytesSent:5,framesEncoded:1})); assert.equal(value.bitrateBps, undefined); });
test('calculates outbound encode, QP, RTT, loss, and codec metrics', () => {
  const sampler = new StatsSampler('outbound');
  sampler.sample(report(
    {id:'v',type:'outbound-rtp',kind:'video',timestamp:1000,bytesSent:1000,framesEncoded:10,totalEncodeTime:0.1,qpSum:100,codecId:'c'},
    {id:'r',type:'remote-inbound-rtp',kind:'video',timestamp:1000,packetsLost:1,packetsReceived:99,roundTripTime:0.01},
    {id:'c',type:'codec',mimeType:'video/VP8'},
  ));
  const value = sampler.sample(report(
    {id:'v',type:'outbound-rtp',kind:'video',timestamp:2000,bytesSent:3000,framesEncoded:30,totalEncodeTime:0.5,qpSum:500,codecId:'c'},
    {id:'r',type:'remote-inbound-rtp',kind:'video',timestamp:2000,packetsLost:3,packetsReceived:197,roundTripTime:0.02},
    {id:'c',type:'codec',mimeType:'video/VP8'},
  ));
  assert.equal(value.averageEncodeTimeMs, 20); assert.equal(value.averageQp, 20);
  assert.equal(value.roundTripTimeMs, 20); assert.equal(value.packetLossRate, 0.02); assert.equal(value.codecMimeType, 'video/VP8');
});
