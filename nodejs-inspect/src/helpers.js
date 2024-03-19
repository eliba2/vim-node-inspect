const path = require('path');
const url = require('url');
const util = require('util');

const print = (value) => {
  const INSPECT_OPTIONS = { colors: true };
  const text = typeof value === 'string' ? value : util.inspect(value, INSPECT_OPTIONS);
  return console.log(text);
};

const getAbsolutePath = (filenameOrURL) => {
  let filename;

  if (filenameOrURL.startsWith('file://')) {
    filename = filenameOrURL;
    try {
      filename = url.fileURLToPath(filenameOrURL);
    } catch (e) {
      // fileURLToPath added in Node 10+
      filename =
        filenameOrURL[7] === '/'
          ? filenameOrURL.substring(8)
          : filenameOrURL.substring(7);
    }
  } else filename = filenameOrURL;

  return filename;
};

const getRelativePath = (filenameOrURL) => {
  const dir = path.join(path.resolve(), 'x').slice(0, -1);
  const filename = getAbsolutePath(filenameOrURL);

  // Change path to relative, if possible
  if (filename.indexOf(dir) === 0) {
    return filename.slice(dir.length);
  }
  return filename;
};

const getCallFrameList = (callFrames, knownScripts) => {
  return callFrames.map((callFrame, idx) => {
    const {
      location: { scriptId, lineNumber, columnNumber },
      functionName
    } = callFrame;
    const name = functionName || '(anonymous)';
    const script = knownScripts[scriptId];
    const relativeUrl =
          (script && getRelativePath(script.url || script)) || '<unknown>';
    const frameLocation =
          `${relativeUrl}:${lineNumber + 1}`;
    return { name, frameLocation };
  }).reverse();
};

module.exports = {
  getAbsolutePath,
  print,
  getCallFrameList
};
