import test from 'node:test';
import assert from 'node:assert/strict';
import { setVideoBandwidth } from '../src/sdp.js';

test('adds a bandwidth line only to the video media section', () => {
  const input = [
    'v=0',
    'm=audio 9 UDP/TLS/RTP/SAVPF 111',
    'c=IN IP4 0.0.0.0',
    'm=video 9 UDP/TLS/RTP/SAVPF 96',
    'c=IN IP4 0.0.0.0',
    'a=sendrecv',
    '',
  ].join('\r\n');

  const output = setVideoBandwidth(input, 500_000);
  assert.match(output, /m=video[^]*c=IN IP4 0\.0\.0\.0\r\nb=AS:500000\r\na=sendrecv/);
  assert.doesNotMatch(output.split('m=video')[0], /b=AS:/);
});

test('replaces an existing video bandwidth declaration', () => {
  const input = 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\nb=AS:2000\r\na=sendrecv\r\n';
  const output = setVideoBandwidth(input, 500_000);
  assert.equal((output.match(/b=AS:/g) || []).length, 1);
  assert.match(output, /b=AS:500000/);
});
