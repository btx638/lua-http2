const http2 = require('http2');

const client = http2.connect("http://localhost:8080", {})

var reqs = 10

for (i = 0; i < reqs; i++) {
  const req = client.request({':path': '/100mb.dat'});

  req.on('response', (headers, flags) => {
  })

  req.on('data', (chunk) => {
  })

  req.on('end', () => {
    if (--reqs == 0) {
        process.exit()
    }
  })
}