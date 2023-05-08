const getAbsolutePath = (filenameOrURL) => {
  let filename

  if (filenameOrURL.startsWith('file://')) {
    filename = filenameOrURL
    try {
      filename = fileURLToPath(filenameOrURL)
    } catch (e) {
      // fileURLToPath added in Node 10+
      filename =
        filenameOrURL[7] === '/'
          ? filenameOrURL.substring(8)
          : filenameOrURL.substring(7)
    }
  } else filename = filenameOrURL

  return filename
}

module.exports = {
  getAbsolutePath
}
