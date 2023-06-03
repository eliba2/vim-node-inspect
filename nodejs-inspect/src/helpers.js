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

module.exports = {
  getAbsolutePath,
  print
};
