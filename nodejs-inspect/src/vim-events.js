const inspector = require('./inspector');
const child = require('./child');
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
        print('Only available when paused(1)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.stepOver();
      break;
    case 'nd_into':
      if (inspector.isRunning) {
        print('Only available when paused(2)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.stepInto();
      break;
    case 'nd_out':
      if (inspector.isRunning) {
        print('Only available when paused(3)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.stepOut();
      break;
    case 'nd_pause':
      if (!inspector.isRunning) {
        print('Only available when running(4)');
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
        print('Only available when paused(5)');
        return;
      }
      inspector.handleResumed();
      inspector.client.Debugger.resume();
      break;
    case 'nd_restart':
      // make an js array out of args, argv-argc style
      child.rerun(message.script, message.args);
      // using setTimeout to make sure the child starts
      setTimeout(async () => {
        await inspector.restart();
      }, 100);
      break;
      /*
    case 'nd_print':
      print(message.txt)
      break
    case 'nd_addbrkpt':
      await setBreakpoint(message.file, message.line)
      break
    case 'nd_removebrkpt':
      await clearBreakpoint(message.file, message.line)
      break
    case 'nd_removeallbrkpts':
      Object.keys(message.breakpoints).map((file) => {
        Object.keys(message.breakpoints[file]).map((line) =>
          clearBreakpoint(file, Number(line))
        )
      })
      break
    case 'nd_setbreakpoints':
      Object.keys(message.breakpoints).map((file) => {
        Object.keys(message.breakpoints[file]).map(
          async (line) => await setBreakpoint(file, Number(line))
        )
      })
      break
    case 'nd_removebreakpoints':
      Object.keys(message.breakpoints).map((file) => {
        Object.keys(message.breakpoints[file]).map(
          async (line) => await removeBreakpoint(file, Number(line))
        )
      })
      break
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
    case 'nd_repl_set_execmode':
      startCliRepl()
      break
*/
    default:
      console.error('unknown message from vim', JSON.stringify(message));
  }
};

module.exports = {
  handleVimEvents
};
