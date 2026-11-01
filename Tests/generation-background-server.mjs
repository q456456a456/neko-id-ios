import http from 'node:http';

// Bind loopback only; this controlled delayed response tests the iOS transport,
// not AI output. No credentials, external requests, or production writes.
let requests = 0;
const port = Number(process.argv[2] ?? 18765);
http.createServer((request, response) => {
  if (request.url === '/status') {
    response.end(JSON.stringify({ requests }));
    return;
  }
  if (request.method !== 'POST' || request.url !== '/generate') {
    response.writeHead(404).end();
    return;
  }
  requests += 1;
  let body = '';
  request.on('data', (chunk) => { body += chunk; });
  request.on('end', () => {
    if (body !== '{"fixture":"background-generation"}') {
      response.writeHead(400).end('Unexpected body');
      return;
    }
    process.stdout.write(`REQUEST_RECEIVED count=${requests}\n`);
    setTimeout(() => {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.write('{"result":');
      setTimeout(() => {
        response.end('"completed-once"}');
        process.stdout.write('RESPONSE_SENT\n');
      }, 100);
    }, 35000);
  });
}).listen(port, '127.0.0.1', () => process.stdout.write(`LISTENING ${port}\n`));
