'use strict';
const test = require('node:test'); const assert = require('node:assert/strict'); const { parseArgs } = require('../src/args');
test('parses helper arguments', () => assert.deepEqual(parseArgs(['--display-id','42','--port','9000','--width','1280','--height','720','--fps','30']), { displayId:'42',port:9000,width:1280,height:720,fps:30 }));
test('requires display id', () => assert.throws(() => parseArgs([]), /display-id/));
test('rejects invalid values', () => assert.throws(() => parseArgs(['--display-id','4','--fps','0']), /fps/));
