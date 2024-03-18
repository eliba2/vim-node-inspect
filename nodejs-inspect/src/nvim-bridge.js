const net = require('net');

const EventEmitter = require('events').EventEmitter;
const MSG_DELIMITER = '&&';

class NvimBridge {
  constructor () {
    if (!NvimBridge.instance) {
      NvimBridge.instance = this;
      this.notifier = new EventEmitter();
      this.client = null;
      this.server = null;
      this.callback = null;
      this.initiated = false;
      this.message_queue = [];
    }
    return NvimBridge.instance;
  }

  send (msg) {
    if (this.client) {
      // console.log("=> sending msg",msg);
      const message = JSON.stringify(msg) + MSG_DELIMITER;
      this.client.write(message);
    } else {
      console.error("can't send event, vim object not set up");
    }
  }

  setEventCallback (callback) {
    this.callback = callback;
    // process any messages in the queue
    while (this.message_queue.length) {
      const message = this.message_queue.pop();
      this.callback(message);
    }
  }

  sendInternalEvent (msg) {
    if (this.callback) {
      this.callback(msg);
    } else {
      this.message_queue.push(msg);
    }
  }

  // the port is determined in vim and is considered safe at this point
  createServer (port) {
    return new Promise((resolve, reject) => {
      this.server = net.createServer((client) => {
        this.client = client;
        // single client support at this time
        this.client.on('data', (data) => {
          // console.log('client says',data.toString(), typeof(data));
          const messageObject = data.toString();
          const message = JSON.parse(messageObject);
          // add bridge to the message
          message.nvim_bridge = this;
          if (this.initiated === false && message.m === 'nd_init') {
            // that should be the first message from the host
            this.initiated = true;
            // serup event handler
            resolve();
          }
          if (this.callback) {
            this.callback(message);
          } else {
            this.message_queue.push(message);
          }
        });
      });
      console.log('Server listening on port', port);
      this.server.listen(port, (c) => {});
    });
  }

  async init (port, callback) {
    this.setEventCallback(callback);
    await this.createServer(port);
  }
}

module.exports = new NvimBridge();
