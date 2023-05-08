var net = require('net');

async function findOpenPort() {
    return new Promise((resolve, reject)=>{
      var server = net.createServer(function(socket) {
        socket.write('Test\r\n');
        socket.pipe(socket);
      });
      server.listen(0, '127.0.0.1');
      server.on('error', function (e) {
        resolve(0);
      });
      server.on('listening', function (e) {
        let listen_port = server.address().port;
        server.close();
        resolve(listen_port);
      });
    });
};

(async function(){
  let port = await findOpenPort();
  process.stdout.write(`${port}`);
  process.exit(0);
})();
