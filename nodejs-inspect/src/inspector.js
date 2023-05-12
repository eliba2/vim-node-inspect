const CDP = require('chrome-remote-interface');
const { getAbsolutePath } = require('./helpers');
const nvimBridge = require('./nvim-bridge');

const knownScripts = [];

class Inspector {
  constructor () {
    if (!Inspector.instance) {
      Inspector.instance = this;
      this.client = null;
      this.isRunning = false;
    }
    return Inspector.instance;
  }

  handleResumed () {
    this.isRunning = true;
  }

  onScriptParsed ({ scriptId, url }) {
    knownScripts[scriptId] = url;
  }

  onDebuggerPaused ({ callFrames, reason }) {
    this.isRunning = false;
    // Save execution context's data
    // currentBacktrace = client.Backtrace.from(callFrames);
    // selectedFrame = currentBacktrace[0];
    const frame = callFrames[0];
    // console.log(frame);
    const { scriptId, lineNumber } = frame.location;

    // const breakType = reason === "other" ? "break" : reason;
    const script = knownScripts[scriptId];
    const scriptUrl = script ? getAbsolutePath(script) : '[unknown]';

    let scriptPrefix = '';
    if (
      scriptUrl?.length &&
    scriptUrl[0] !== '/' &&
    scriptUrl[0] !== '[' &&
    process.platform !== 'win32'
    ) {
      scriptPrefix = '/';
    }
    /* notify nvim */
    const tokens = {};
    // if (doAutoWatches) {
    // tokens = await getTokens(`${scriptPrefix}${scriptUrl}`); // call get arguments and set the parameters to the stop function to display in the watch window
    // }
    const m = {
      m: 'nd_stopped',
      file: `${scriptPrefix}${scriptUrl}`,
      line: lineNumber + 1,
      backtrace: [], // Backtrace.getList(callFrames),
      tokens
    };
    nvimBridge.send(m);
  }

  start () {
    console.log('========= start ');
    CDP(async (ifClient) => {
      this.client = ifClient;
      const { Debugger, Runtime } = ifClient;
      try {
        Debugger.paused((props) => {
          console.log('paused !');
          this.onDebuggerPaused(props);
        // client.Debugger.resume();
        // client.close();
        });
        Debugger.scriptParsed((props) => {
          this.onScriptParsed(props);
        });
        await Runtime.runIfWaitingForDebugger();
        await Debugger.enable();
      } catch (err) {
        console.error(err);
      } finally {
      // client.close();
      }
    }).on('error', (err) => {
      console.error(err);
    });
  }

  async stop () {
    return new Promise((resolve, reject) => {
      knownScripts.length = 0;
      this.isRunning = false;
      if (this.client) {
        this.client.close().then(() => {
          resolve();
        });
      } else {
        resolve();
      }
    });
  }

  async restart () {
    await this.stop();
    this.start();
  }
}

module.exports = new Inspector();
