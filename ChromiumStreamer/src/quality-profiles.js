'use strict';

const PROFILE_ORDER = ['constrained', 'motion', 'balanced', 'detail'];
const PROFILE_FACTORS = Object.freeze({
  detail: { bitrate: 1 },
  balanced: { bitrate: 0.7 },
  motion: { bitrate: 0.6 },
  constrained: { bitrate: 0.35, fpsCap: 30 },
});

function profileSettings(name, baseBitrateBps, baseFps) {
  const factor = PROFILE_FACTORS[name];
  if (!factor) throw new Error(`Unknown quality profile: ${name}`);
  return {
    profile: name,
    scale: 1,
    maxBitrateBps: Math.max(100_000, Math.round(baseBitrateBps * factor.bitrate)),
    maxFps: Math.max(1, Math.min(baseFps, factor.fpsCap || baseFps)),
  };
}

module.exports = { PROFILE_ORDER, PROFILE_FACTORS, profileSettings };
