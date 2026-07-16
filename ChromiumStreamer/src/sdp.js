export function setVideoBandwidth(sdp, kilobitsPerSecond) {
  const lines = sdp.split(/\r?\n/);
  const videoStart = lines.findIndex((line) => line.startsWith('m=video '));
  if (videoStart < 0) return sdp;

  let videoEnd = lines.findIndex((line, index) => index > videoStart && line.startsWith('m='));
  if (videoEnd < 0) videoEnd = lines.length;

  for (let index = videoEnd - 1; index > videoStart; index -= 1) {
    if (/^b=(AS|TIAS):/.test(lines[index])) lines.splice(index, 1);
  }

  const connectionIndex = lines.findIndex(
    (line, index) => index > videoStart && index < videoEnd && line.startsWith('c='),
  );
  const insertionIndex = connectionIndex >= 0 ? connectionIndex + 1 : videoStart + 1;
  lines.splice(insertionIndex, 0, `b=AS:${Math.round(kilobitsPerSecond)}`);
  return lines.join('\r\n');
}
