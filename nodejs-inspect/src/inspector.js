const CDP = require('chrome-remote-interface');
const { getAbsolutePath } = require('./helpers');
const nvimBridge = require('./nvim-bridge');
const helpers = require('./helpers');

class Inspector {
  constructor () {
    if (!Inspector.instance) {
      Inspector.instance = this;
      this.client = null;
      this.isRunning = false;
      /* script source to id map */
      this.knownScripts = {};
      /* breakpoints likst */
      this.knownBreakpoints = [];
      /* selected frame */
      this.selectedFrame = null;
    }
    return Inspector.instance;
  }

  handleResumed () {
    this.isRunning = true;
  }

  async onScriptParsed ({ scriptId, url }) {
    this.knownScripts[scriptId] = url;
  }

  async setBreakpoint (script, lineNumber, condition, silent) {
    const { Debugger } = this.client;
    console.log('set ', script, lineNumber);
    // get the scriptId
    const scriptId = Object.keys(this.knownScripts).find(s => this.knownScripts[s] === `file://${script}`);
    if (!scriptId) {
      const m = { m: 'nd_brk_failed', file: script, line: lineNumber };
      nvimBridge.send(m);
      return;
    }
    Debugger.setBreakpoint({
      location: {
        scriptId,
        lineNumber
      }
    }).then(async ({ breakpointId, actualLocation: location }) => {
      const isExisting = this.knownBreakpoints.some((bp) => {
        if (bp.breakpointId === breakpointId) {
          Object.assign(bp, { location });
          return true;
        }
        return false;
      });
      if (!isExisting) {
        this.knownBreakpoints.push({ breakpointId, location });
      }
      // notify vim the breakpoint was resolved
      let resolveFile = this.knownScripts[location.scriptId];
      if (resolveFile.startsWith('file://')) {
        resolveFile = resolveFile.slice(7);
      }
      const m = { m: 'nd_brk_resolved', file: resolveFile, line: location.lineNumber };
      nvimBridge.send(m);
    }).catch(e => {
      /* can't set breakpoint at location */
      if (e.message && e.message.indexOf('Could not resolve breakpoint') !== -1) {
        helpers.print('Breakpoint cannot be set at location');
      }
      const m = { m: 'nd_brk_failed', file: script, line: lineNumber };
      nvimBridge.send(m);
      console.error(JSON.stringify(e));
    });
  }

  async removeBreakpoint (script, lineNumber) {
    console.log('removing ', script, lineNumber);
    const { Debugger } = this.client;
    const breakpoint = this.knownBreakpoints.find(({ location }) => {
      if (!location) return false;
      const bpscript = this.knownScripts[location.scriptId];
      if (!bpscript) return false;
      return (
        bpscript.indexOf(script) !== -1 && (location.lineNumber) === lineNumber
      );
    });
    if (!breakpoint) {
      console.error(`Could not find breakpoint at ${script}:${lineNumber}`);
      return Promise.resolve();
    }
    return Debugger.removeBreakpoint({ breakpointId: breakpoint.breakpointId })
      .then(() => {
        const idx = this.knownBreakpoints.indexOf(breakpoint);
        this.knownBreakpoints.splice(idx, 1);
      });
  }

  async onDebuggerPaused ({ data, callFrames, reason, asyncStackTrace }) {
    this.isRunning = false;

    const { Runtime } = this.client;
    const { scopeChain } = callFrames[0];
    const localScope = scopeChain.find(scope => scope.type === 'local');

    if (localScope) {
      const { objectId } = localScope.object;
      const properties = await Runtime.getProperties({ objectId });
      if (properties && properties.result) {
        const dontDisplay = {
          exports: true,
          require: true,
          module: true,
          __filename: true,
          __dirname: true
        };
        const tokens = properties.result.filter(s => !dontDisplay[s.name]);
        console.log(tokens);
      }
    }

    const frame = callFrames[0];
    const { scriptId, lineNumber } = frame.location;
    this.selectedFrame = frame;

    // const breakType = reason === "other" ? "break" : reason;
    const script = this.knownScripts[scriptId];
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
      backtrace: helpers.getCallFrameList(callFrames, this.knownScripts),
      tokens
    };
    nvimBridge.send(m);
  }

  async start (target) {
    const url = new URL(target.startsWith('http') ? target : `http://${target}`);
    const { hostname, port } = url;
    this.client = await CDP({ host: hostname, port: Number(port) });
    const { Debugger, Runtime } = this.client;
    try {
      Debugger.paused(async (props) => {
        await this.onDebuggerPaused(props);
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
    this.client.on('ready', () => {
      const vimReadyMessage = { m: 'nd_node_socket_ready' };
      nvimBridge.send(vimReadyMessage);
    });
    this.client.on('disconnect', () => {
      const vimSockLostMessage = { m: 'nd_node_socket_closed' };
      nvimBridge.send(vimSockLostMessage);
    });
    this.client.on('error', (err) => {
      console.error(err);
    });
  }

  async stop () {
    return new Promise((resolve, reject) => {
      this.knownScripts.length = 0;
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

  async evaluate (code) {
    const inspector = new Inspector();
    if (inspector.selectedFrame) {
      const response = await inspector.client.Debugger.evaluateOnCallFrame({
        callFrameId: inspector.selectedFrame.callFrameId,
        expression: code,
        objectGroup: 'node-inspect',
        // generatePreview: true,
        includeCommandLineAPI: true,
        silent: false
      });
      if (response?.result?.subtype === 'error') {
        console.error('!< ', response.result.description);
      } else console.log('<', response.result.description);
      return response;
    }
    return inspector.client.Runtime.evaluate({
      expression: code,
      objectGroup: 'node-inspect',
      generatePreview: true
    });
  }
}

module.exports = new Inspector();
