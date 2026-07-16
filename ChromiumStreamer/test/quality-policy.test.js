'use strict';
const test = require('node:test'); const assert = require('node:assert/strict'); const { QualityPolicy } = require('../src/quality-policy');
test('reduces quality after sustained motion and restores it after stability', () => { const value = new QualityPolicy(); assert.equal(value.observe(.2),null); value.observe(.2); value.observe(.2); assert.equal(value.observe(.2),.5); value.observe(0); value.observe(0); value.observe(0); assert.equal(value.observe(0),1); });
