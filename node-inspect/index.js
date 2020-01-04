function onBufWrite() {
  console.log('Buffer written!');
}

module.exports = (plugin) => {
  function setLine() {
    plugin.nvim.setLine('A line, for your troubles');
  }
  plugin.registerCommand('SetMyLine', [plugin.nvim.buffer, setLine]);
  plugin.registerAutocmd('BufWritePre', onBufWrite, { pattern: '*' });
};


/*
module.exports = plugin => {
  plugin.setOptions({ dev: false });

  plugin.registerCommand('ND', async () => {
      try {
        await plugin.nvim.outWrite('Dayman (ah-ah-ah) \n');
      } catch (err) {
        console.error(err);
      }
    }, { sync: false });

  //plugin.registerFunction('ND',() => {
    //return plugin.nvim.setLine('May I offer you an egg in these troubling times')
      //.then(() => console.log('Line should be set'))
  //}, {sync: false})

};
*/
