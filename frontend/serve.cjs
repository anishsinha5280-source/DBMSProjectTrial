// Frontend-only static server. The existing backend remains separate and unchanged.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const port = Number(process.env.FRONTEND_PORT || 5173);
const publicFiles = new Set(['index.html', 'styles.css', 'app.js']);
const types = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.js':'text/javascript; charset=utf-8' };
http.createServer((req, res) => {
  if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405, {Allow:'GET, HEAD'}); return res.end(); }
  const name = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
  if (!publicFiles.has(name)) { res.writeHead(404); return res.end('Not found'); }
  fs.readFile(path.join(root, name), (error, bytes) => {
    if (error) { res.writeHead(500); return res.end('Unable to read frontend file'); }
    res.writeHead(200, {'Content-Type':types[path.extname(name)], 'Cache-Control':'no-cache', 'X-Content-Type-Options':'nosniff'});
    res.end(req.method === 'HEAD' ? undefined : bytes);
  });
}).listen(port, '127.0.0.1', () => console.log(`GridSync frontend: http://localhost:${port}`));
