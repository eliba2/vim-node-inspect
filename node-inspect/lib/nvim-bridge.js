const socket_path = '/tmp/node-inspect.sock';
const net = require('net');
var EventEmitter = require('events').EventEmitter;
const MSG_DELIMITER = '&&';


class NvimBridge {

	constructor() {
		this.notifier = new EventEmitter();
		this.client = null;
		this.server = null;
		this.callback = null;
		this.initiated = false;
		this.message_queue = [];
	}

	send(msg) {
		if (this.client) {
			// console.log("=> sending msg",msg);
			let message = JSON.stringify(msg) + MSG_DELIMITER;
			this.client.write(message);
		}
		else {
			console.error("can't send event, vim object not set up");
		}
	}

	setEventCallback(callback) {
		this.callback = callback;
		// process any messages in the queue
		while (this.message_queue.length) {
			let message = this.message_queue.pop();
			this.callback(message);
		}

	}


	sendInternalEvent(msg) {
		if (this.callback) {
			this.callback(msg);
		}
		else {
			this.message_queue.push(msg);
		}
	}


  // the port is determined in vim and is considered safe at this point
	createServer(port) {
		return new Promise((resolve,reject) => {
			this.server = net.createServer((client) => {
				this.client = client;
				// single client support at this time
				this.client.on('data', (data) => {
					//console.log('client says',data.toString(), typeof(data));
					let message_object = data.toString();
					let message = JSON.parse(message_object);
					if (this.initiated == false &&  message.m == 'nd_init') {
						// that should be the first message from the host
						this.initiated = true;
						resolve();
					}
					if (this.callback) {
						this.callback(message);
					}
					else {
						this.message_queue.push(message);
					}
				});
			});
			this.server.listen(port, (c) => {
			});
		});
	}
}

module.exports = NvimBridge;
