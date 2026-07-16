'use strict';

class QualityPolicy {
  constructor() { this.motionSamples = 0; this.stableSamples = 0; this.scale = 1; }
  observe(changeRatio) {
    if (changeRatio >= 0.1) { this.motionSamples += 1; this.stableSamples = 0; }
    else { this.stableSamples += 1; this.motionSamples = 0; }
    if (this.scale === 1 && this.motionSamples >= 4) { this.scale = 0.5; return this.scale; }
    if (this.scale === 0.5 && this.stableSamples >= 4) { this.scale = 1; return this.scale; }
    return null;
  }
  reset() { this.motionSamples = 0; this.stableSamples = 0; this.scale = 1; }
}

module.exports = { QualityPolicy };
