'use strict';

const VERSION = 1;
const PROFILES = new Set(['detail', 'balanced', 'motion', 'constrained']);
const SAMPLE_BOUNDS = Object.freeze({
  timestamp: [0, Number.MAX_SAFE_INTEGER], bitrateBps: [0, 1_000_000_000], framesPerSecond: [0, 240], framesDelta: [0, 1_000_000],
  averageEncodeTimeMs: [0, 60_000], averageQp: [0, 255], playoutDelayMs: [0, 60_000], jitterSeconds: [0, 60],
  packetLossRate: [0, 1], roundTripTimeMs: [0, 60_000], framesDroppedDelta: [0, 1_000_000], freezeCountDelta: [0, 1_000_000],
  width: [1, 32_768], height: [1, 32_768],
});

function validNumber(value, minimum, maximum) { return Number.isFinite(value) && value >= minimum && value <= maximum; }
function validProfile(value) { return PROFILES.has(value); }
function validStatsSample(sample) {
  if (!sample || typeof sample !== 'object' || Array.isArray(sample)) return false;
  if (!validNumber(sample.timestamp, ...SAMPLE_BOUNDS.timestamp)) return false;
  for (const [key, bounds] of Object.entries(SAMPLE_BOUNDS)) {
    if (key !== 'timestamp' && sample[key] !== undefined && !validNumber(sample[key], ...bounds)) return false;
  }
  if (sample.qualityLimitationReason !== undefined && (typeof sample.qualityLimitationReason !== 'string' || sample.qualityLimitationReason.length > 64)) return false;
  return sample.codecMimeType === undefined || (typeof sample.codecMimeType === 'string' && sample.codecMimeType.length <= 128);
}

function decodeMessage(value) {
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : JSON.parse(new TextDecoder().decode(value));
    if (!parsed || parsed.version !== VERSION || typeof parsed.type !== 'string') return null;
    if (parsed.type === 'quality-command') {
      if (!Number.isSafeInteger(parsed.sequence) || parsed.sequence < 0 || !validProfile(parsed.profile)) return null;
      if (!validNumber(parsed.scale, 0.25, 1) || !validNumber(parsed.maxFps, 1, 240)) return null;
      if (!validNumber(parsed.maxBitrateBps, 100_000, 1_000_000_000)) return null;
    } else if (parsed.type === 'quality-applied') {
      if (!Number.isSafeInteger(parsed.sequence) || parsed.sequence < 0 || !validProfile(parsed.profile)) return null;
      if (!validNumber(parsed.trackWidth, 1, 32_768) || !validNumber(parsed.trackHeight, 1, 32_768)) return null;
      if (!validNumber(parsed.maxFps, 1, 240) || !validNumber(parsed.maxBitrateBps, 100_000, 1_000_000_000)) return null;
    } else if (parsed.type === 'host-stats') {
      if (!validStatsSample(parsed.sample)) return null;
    } else {
      return null;
    }
    return parsed;
  } catch { return null; }
}

function encodeMessage(message) { return JSON.stringify({ version: VERSION, ...message }); }

module.exports = { VERSION, decodeMessage, encodeMessage };
