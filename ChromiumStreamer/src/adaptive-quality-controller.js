'use strict';

const { PROFILE_ORDER, profileSettings } = require('./quality-profiles');

const DEFAULT_THRESHOLDS = Object.freeze({
  severePlayoutMs: 120, pressurePlayoutMs: 70, healthyPlayoutMs: 45,
  severeLoss: 0.08, pressureLoss: 0.03, healthyLoss: 0.01,
  pressureRttMs: 150, encodeBudgetRatio: 0.8,
  motionHigh: 0.12, motionLow: 0.025,
  pressureSamples: 3, recoverySamples: 8,
  downgradeCooldownMs: 2_000, upgradeCooldownMs: 8_000,
});

class AdaptiveQualityController {
  constructor(options = {}) {
    this.thresholds = { ...DEFAULT_THRESHOLDS, ...options.thresholds };
    this.baseBitrateBps = options.baseBitrateBps || 500_000_000; this.baseFps = options.baseFps || 60;
    this.profile = options.initialProfile || 'detail';
    this.lastChangeAt = -Infinity; this.candidate = undefined; this.candidateCount = 0;
  }
  observe(sample, now = Date.now()) {
    const t = this.thresholds;
    const receiver = sample.receiver || {}; const host = sample.host || {};
    const loss = Math.max(receiver.packetLossRate ?? 0, host.packetLossRate ?? 0);
    const playout = receiver.playoutDelayMs;
    const transportPressure = host.roundTripTimeMs !== undefined && host.roundTripTimeMs > t.pressureRttMs;
    const encodePressure = host.averageEncodeTimeMs !== undefined && host.averageEncodeTimeMs > (1000 / this.baseFps) * t.encodeBudgetRatio;
    const severe = loss > t.severeLoss || (playout !== undefined && playout > t.severePlayoutMs);
    const pressure = loss > t.pressureLoss || (playout !== undefined && playout > t.pressurePlayoutMs) || transportPressure || encodePressure || ['bandwidth', 'cpu'].includes(host.qualityLimitationReason);
    const healthy = loss < t.healthyLoss && (playout === undefined || playout < t.healthyPlayoutMs) && !transportPressure && !encodePressure && !['bandwidth', 'cpu'].includes(host.qualityLimitationReason);
    let target = this.profile; let reason = 'hold'; let required = 1;
    const index = PROFILE_ORDER.indexOf(this.profile);
    if (severe) { target = PROFILE_ORDER[Math.max(0, index - 2)]; reason = 'severe-congestion'; }
    else if (pressure) { target = PROFILE_ORDER[Math.max(0, index - 1)]; reason = 'sustained-pressure'; required = t.pressureSamples; }
    else if (healthy && sample.motionRatio >= t.motionHigh && index > PROFILE_ORDER.indexOf('motion')) { target = 'motion'; reason = 'high-motion'; required = t.pressureSamples; }
    else if (healthy && (index === PROFILE_ORDER.indexOf('constrained') || (sample.motionRatio <= t.motionLow && index < PROFILE_ORDER.indexOf('detail')))) {
      target = PROFILE_ORDER[Math.min(PROFILE_ORDER.length - 1, index + 1)]; reason = 'healthy-recovery'; required = t.recoverySamples;
    }
    if (target === this.profile) { this.candidate = undefined; this.candidateCount = 0; return null; }
    if (target !== this.candidate) { this.candidate = target; this.candidateCount = 1; } else this.candidateCount += 1;
    if (this.candidateCount < required) return null;
    const upgrading = PROFILE_ORDER.indexOf(target) > index;
    const cooldown = upgrading ? t.upgradeCooldownMs : t.downgradeCooldownMs;
    if (now - this.lastChangeAt < cooldown) return null;
    this.profile = target; this.lastChangeAt = now; this.candidate = undefined; this.candidateCount = 0;
    return { profile: target, reason, settings: profileSettings(target, this.baseBitrateBps, this.baseFps) };
  }
  reset(profile = 'detail') { this.profile = profile; this.lastChangeAt = -Infinity; this.candidate = undefined; this.candidateCount = 0; }
}

module.exports = { AdaptiveQualityController, DEFAULT_THRESHOLDS };
