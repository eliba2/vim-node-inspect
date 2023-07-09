const repl = require('repl');
const inspector = require('./inspector');

class Repl {
  constructor () {
    if (!Repl.instance) {
      Repl.instance = this;
      this.repl = null;
    }
    return Repl.instance;
  }

  start ({ child, cdp }) {
    const replOptions = {
      prompt: '>> ',
      eval: inspector.evaluate,
      useGlobal: true,
      ignoreUndefined: false,
      useColors: true
    };

    this.repl = repl.start(replOptions);
  }
}

module.exports = new Repl();
