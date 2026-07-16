'use strict';

function parseArgs(argv) {
  const result = { displayId: '', port: 8080, width: 1920, height: 1080, fps: 60 };
  const names = { '--display-id': 'displayId', '--port': 'port', '--width': 'width', '--height': 'height', '--fps': 'fps' };
  for (let index = 0; index < argv.length; index += 1) {
    const key = names[argv[index]];
    if (!key || index + 1 >= argv.length) throw new Error(`Invalid helper option: ${argv[index]}`);
    const raw = argv[++index];
    if (key === 'displayId') result[key] = raw;
    else {
      const number = Number(raw);
      if (!Number.isInteger(number) || number <= 0) throw new Error(`Invalid ${argv[index - 1]}: ${raw}`);
      result[key] = number;
    }
  }
  if (!result.displayId) throw new Error('--display-id is required');
  return result;
}

module.exports = { parseArgs };
