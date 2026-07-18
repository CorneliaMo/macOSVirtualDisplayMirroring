'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { profileSettings } = require('../src/quality-profiles');
test('keeps every automatic profile at native resolution in phase B', () => { for (const name of ['detail','balanced','motion','constrained']) assert.equal(profileSettings(name, 100_000_000, 60).scale, 1); });
test('limits constrained bitrate and frame rate', () => assert.deepEqual(profileSettings('constrained', 100_000_000, 60), { profile:'constrained',scale:1,maxBitrateBps:35_000_000,maxFps:30 }));
test('does not halve an already-low configured frame rate', () => assert.equal(profileSettings('constrained', 100_000_000, 24).maxFps, 24));
