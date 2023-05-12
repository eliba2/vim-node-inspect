const { spawn } = require('child_process');
const nvimBridge = require('./nvim-bridge');
const inspector = require('./inspector');

class InspectChild {
  constructor () {
    if (!InspectChild.instance) {
      InspectChild.instance = this;
      this.child = null;
    }
    return InspectChild.instance;
  }

  async kill () {
    return new Promise((resolve, reject) => {
      if (this.child) {
        this.child.kill();
        this.child = null;
      }
      resolve();
    });
  }

  init (target) {
    process.on('uncaughtException', (e) => {
      console.error('Cant start nodejs-inspect');
      console.error(e.message);
      console.error(e.stack);
    });

    /* starting nodejs in case of launch */
    this.child = spawn('node', ['--inspect-brk=9222', target]);

    this.child.stdout.on('data', (data) => {
      console.log(`>> ${data}`);
    });

    this.child.stderr.on('data', (data) => {
      if (/Waiting for the debugger to disconnect\.\.\.\n$/.test(data)) {
        this.kill().then(() => {
          inspector.stop().then(() => {
            const m = { m: 'nd_halt' };
            nvimBridge.send(m);
          });
        });
        return;
      }
      console.error(`!> ${data}`);
    });

    this.child.on('close', (code) => {
      console.log(`!!> child closed ${code}`);
    });

    this.child.on('error', (code) => {
      console.log(`%> child error ${code}`);
    });
  }

  rerun (script, scriptArgs) {
    this.init(script);
  }
}

module.exports = new InspectChild();
