const inspector = require('./inspector');
const child = require('./child');
const helpers = require('./helpers');
let doAutoWatches = 0;

const handleVimEvents = async (message) => {
  console.log('processing ', message.m);
  switch (message.m) {
    case 'nd_init':
      // init message. set state
      if (message.autoWatches === 0) {
        doAutoWatches = 0;
      }
      // env file config will be overridden by specific env file configuration
      if (message.envFile) {
        const config = require('../../dotenv').config({ path: message.envFile });
      }
      if (message.env) {
        try {
          const envs = JSON.parse(message.env);
          Object.keys(envs).map((s) => (process.env[s] = envs[s]));
        } catch (e) {
          console.log('error parsing env object', e);
        }
      }
      break;
    case 'nd_next':
      if (inspector.isRunning) {
        helpers.print('Only available when paused(1)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.stepOver();
      break;
    case 'nd_into':
      if (inspector.isRunning) {
        helpers.print('Only available when paused(2)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.stepInto();
      break;
    case 'nd_out':
      if (inspector.isRunning) {
        helpers.print('Only available when paused(3)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.stepOut();
      break;
    case 'nd_pause':
      if (!inspector.isRunning) {
        helpers.print('Only available when running(4)');
        return;
      }
      inspector.client.Debugger.pause();
      break;
    case 'nd_kill':
      child.kill();
      await inspector.stop();
      process.exit(0);
      break;
    case 'nd_continue':
      if (inspector.isRunning) {
        helpers.print('Only available when paused(5)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.resume();
      break;
    case 'nd_restart':
      child.rerun(message.script, message.args);
      // using setTimeout to make sure the child starts
      setTimeout(async () => {
        await inspector.restart();
      }, 100);
      break;
    case 'nd_print':
      helpers.print(message.txt);
      break;
    case 'nd_addbrkpt':
      await inspector.setBreakpoint(message.file, message.line);
      break;
    case 'nd_removebrkpt':
      await inspector.removeBreakpoint(message.file, message.line);
      break;
    case 'nd_removeallbrkpts':
      // eslint-disable-next-line array-callback-return
      Object.keys(message.breakpoints).map(file => {
        Object.keys(message.breakpoints[file]).map((line) =>
          inspector.removeBreakpoint(file, Number(line))
        );
      });
      break;
    case 'nd_setbreakpoints':
      // eslint-disable-next-line array-callback-return
      Object.keys(message.breakpoints).map(file => {
        Object.keys(message.breakpoints[file]).map(
          async (line) => await inspector.setBreakpoint(file, Number(line))
        );
      });
      break;
    // NOT USED ??
    case 'nd_removebreakpoints':
      // eslint-disable-next-line array-callback-return
      Object.keys(message.breakpoints).map((file) => {
        Object.keys(message.breakpoints[file]).map(
          async (line) => await inspector.removeBreakpoint(file, Number(line))
        );
      });
      break;

    case 'nd_resolveobject':
      {
        const tokens = await inspector.resolveObject(message.objectId);
        const m = {
          m: 'nd_resolvedobject',
          objectId: message.objectId,
          tokens
        };
        message.nvim_bridge.send(m);
      }
      break;
      /*
    case 'nd_verifyrestart':
      if (vimGetScripts()[message.file]) {
        const m = { m: 'nd_restartrequired' }
        message.nvim_bridge.send(m)
      }
      break
    case 'nd_updatewatches':
      const watches = await resolveWatches(message.watches)
      const m = {
        m: 'nd_watchesresolved',
        watches
      }
      message.nvim_bridge.send(m)
      break
*/
    default:
      console.error('unknown message from vim', JSON.stringify(message));
  }
};

module.exports = {
  handleVimEvents
};
