const net = require('net');

async function findOpenPort () {
  return new Promise((resolve, reject) => {
    const server = net.createServer(function (socket) {
      socket.write('Test\r\n');
      socket.pipe(socket);
    });
    server.listen(0, '127.0.0.1');
    server.on('error', function (e) {
      resolve(0);
    });
    server.on('listening', function (e) {
      const listenPort = server.address().port;
      server.close();
      resolve(listenPort);
    });
  });
}

if (require.main === module) {
  (async function () {
    const port = await findOpenPort();
    process.stdout.write(`${port}`);
    process.exit(0);
  })();
}

module.exports = findOpenPort;
