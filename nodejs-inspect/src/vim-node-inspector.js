const bridge = require('./nvim-bridge');
const { handleVimEvents } = require('./vim-events');
const inspector = require('./inspector');
const child = require('./child');
const findOpenPort = require('./find_port');

const startInspect = async (argv = process.argv.slice(2)) => {
  const request = argv[0];
  const port = argv[1];
  const target = argv[2];
  let url;
  if (request === 'launch') {
    /* find a suitable port for executing node, set url */
    const nodePort = await findOpenPort();
    /* start client process */
    child.init(target, nodePort, argv.slice(3));
    url = `localhost:${nodePort}`;
  } else {
    url = target;
  }
  /* start node bridge */
  await bridge.init(port, handleVimEvents);
  /* start debugger */
  inspector.start(url);
};

module.exports = {
  start: startInspect
};
