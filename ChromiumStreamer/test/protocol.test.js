'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { decodeMessage, encodeMessage } = require('../src/protocol');
test('round trips a valid quality command', () => { const value = { type:'quality-command',sequence:2,profile:'detail',scale:1,maxFps:60,maxBitrateBps:1_000_000 }; assert.deepEqual(decodeMessage(encodeMessage(value)), { version:1,...value }); });
test('rejects malformed and unsafe quality commands', () => { assert.equal(decodeMessage('{'), null); assert.equal(decodeMessage('{"version":2,"type":"host-stats"}'), null); assert.equal(decodeMessage(encodeMessage({ type:'quality-command',sequence:1,profile:'bad',scale:.5,maxFps:999,maxBitrateBps:1 })), null); });
test('allows future bounded capture scales and rejects unknown message types', () => { const value = { type:'quality-command',sequence:3,profile:'motion',scale:.75,maxFps:60,maxBitrateBps:2_000_000 }; assert.ok(decodeMessage(encodeMessage(value))); assert.equal(decodeMessage(encodeMessage({ type:'surprise' })), null); });
test('strictly validates host telemetry and quality acknowledgements', () => {
  assert.ok(decodeMessage(encodeMessage({ type:'host-stats',sample:{ timestamp:10,bitrateBps:500_000,packetLossRate:.01,qualityLimitationReason:'none' } })));
  assert.equal(decodeMessage(encodeMessage({ type:'host-stats',sample:{ timestamp:10,packetLossRate:2 } })), null);
  assert.ok(decodeMessage(encodeMessage({ type:'quality-applied',sequence:1,profile:'detail',trackWidth:1920,trackHeight:1080,maxFps:60,maxBitrateBps:5_000_000 })));
  assert.equal(decodeMessage(encodeMessage({ type:'quality-applied',sequence:1,profile:'detail',trackWidth:0,trackHeight:1080,maxFps:60,maxBitrateBps:5_000_000 })), null);
});
