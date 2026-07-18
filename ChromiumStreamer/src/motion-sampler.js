import pixelmatch from 'pixelmatch';

export class MotionSampler {
  constructor(video, canvas, alpha = 0.35) { this.video = video; this.canvas = canvas; this.alpha = alpha; this.previous = undefined; this.ema = 0; }
  sample() {
    if (document.hidden || this.video.readyState < 2 || !this.video.videoWidth) return undefined;
    const width = Math.max(1, Math.floor(this.video.videoWidth / 8)); const height = Math.max(1, Math.floor(this.video.videoHeight / 8));
    this.canvas.width = width; this.canvas.height = height;
    const context = this.canvas.getContext('2d', { willReadFrequently: true }); context.drawImage(this.video, 0, 0, width, height);
    const current = context.getImageData(0, 0, width, height); let ratio;
    if (this.previous) ratio = pixelmatch(this.previous.data, current.data, null, width, height, { threshold: 0.1 }) / (width * height);
    this.previous = current;
    if (ratio === undefined) return undefined;
    this.ema = this.ema * (1 - this.alpha) + ratio * this.alpha; return this.ema;
  }
  reset() { this.previous = undefined; this.ema = 0; }
}
