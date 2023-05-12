const bridge = require('./nvim-bridge');
const { handleVimEvents } = require('./vim-events');
const inspector = require('./inspector');
const child = require('./child');

const startInspect = async (argv = process.argv.slice(2)) => {
  console.log('starting nodejs-inspect');

  const port = argv[0];
  const target = argv[1];
  /* start client process */
  child.init(target);
  /* start node bridge */
  await bridge.init(port, handleVimEvents);
  /* start debugger */
  inspector.start();
};

module.exports = {
  start: startInspect
};
