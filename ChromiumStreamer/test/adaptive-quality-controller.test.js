'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { AdaptiveQualityController } = require('../src/adaptive-quality-controller');

test('drops two profiles immediately for severe congestion', () => {
  const controller = new AdaptiveQualityController();
  assert.deepEqual(controller.observe({ receiver: { playoutDelayMs: 150 }, motionRatio: 0 }, 0), { profile: 'motion', reason: 'severe-congestion', settings: { profile:'motion',scale:1,maxBitrateBps:300_000_000,maxFps:60 } });
});
test('requires sustained pressure and respects downgrade cooldown', () => {
  const controller = new AdaptiveQualityController(); const sample = { receiver: { packetLossRate: 0.04 }, motionRatio: 0 };
  assert.equal(controller.observe(sample, 0), null); assert.equal(controller.observe(sample, 500), null);
  const decision = controller.observe(sample, 1000); assert.equal(decision.profile, 'balanced'); assert.equal(decision.settings.maxBitrateBps, 350_000_000);
  assert.equal(controller.observe(sample, 1500), null); assert.equal(controller.observe(sample, 2000), null); assert.equal(controller.observe(sample, 2500), null);
});
test('recovers one step only after healthy samples and cooldown', () => {
  const controller = new AdaptiveQualityController({ initialProfile: 'constrained' });
  const sample = { receiver: { playoutDelayMs: 10, packetLossRate: 0 }, host: { qualityLimitationReason: 'none' }, motionRatio: 0 };
  for (let index = 0; index < 7; index += 1) assert.equal(controller.observe(sample, index * 1000), null);
  assert.equal(controller.observe(sample, 8000).profile, 'motion');
});
test('holds motion profile while high motion continues', () => {
  const controller = new AdaptiveQualityController({ initialProfile: 'motion' });
  const sample = { receiver: { playoutDelayMs: 10, packetLossRate: 0 }, host: { qualityLimitationReason: 'none' }, motionRatio: 0.2 };
  for (let index = 0; index < 20; index += 1) assert.equal(controller.observe(sample, index * 1000), null);
  assert.equal(controller.profile, 'motion');
});
test('missing optional metrics are neutral and do not emit duplicate decisions', () => {
  const controller = new AdaptiveQualityController();
  for (let index = 0; index < 20; index += 1) assert.equal(controller.observe({ motionRatio: 0 }, index * 1000), null);
  assert.equal(controller.profile, 'detail');
});
test('treats sustained RTT and encoder pressure as downgrade signals', () => {
  for (const host of [{ roundTripTimeMs: 200 }, { averageEncodeTimeMs: 20 }]) {
    const controller = new AdaptiveQualityController({ baseFps: 60 }); const sample = { receiver: {}, host, motionRatio: 0 };
    assert.equal(controller.observe(sample, 0), null); assert.equal(controller.observe(sample, 500), null);
    assert.equal(controller.observe(sample, 1000).profile, 'balanced');
  }
});
