import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return readFileSync(path.join(ROOT, rel), 'utf8');
}

test('V25: PaaS Caddyfile + socket-proxy contract enforces on_demand_tls ask and isolation', () => {
  const caddy = read('Caddyfile.template');
  assert.match(caddy, /on_demand_tls\s*\{/);
  assert.match(caddy, /ask\s+http:\/\/mw-cp:4440\/paas\/caddy\/ask/);
  assert.match(caddy, /\*\.paas\.\{\$MW_DOMAIN:mw\.local\}/);

  const proxy = read('docker-compose.proxy.yml');
  assert.match(proxy, /DOCKER_HOST:\s*"tcp:\/\/docker-socket-proxy:2375"/);
});

test('V25: PaaS deploy lifecycle + Caddy on_demand_tls ask contract', async () => {
  const activeDeployments = new Map([
    ['app-alpha.paas.mw.local', { status: 'running', containerId: 'ctr-alpha-01' }],
  ]);

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/paas/caddy/ask') {
      const domain = url.searchParams.get('domain') || '';
      const dep = activeDeployments.get(domain);
      if (dep && dep.status === 'running') {
        res.writeHead(200, { 'content-type': 'text/plain' });
        res.end('ok');
        return;
      }
      res.writeHead(403, { 'content-type': 'text/plain' });
      res.end('denied');
      return;
    }
    res.writeHead(404);
    res.end('not found');
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    const allowed = await fetch(`http://127.0.0.1:${port}/paas/caddy/ask?domain=app-alpha.paas.mw.local`);
    assert.equal(allowed.status, 200);

    const denied = await fetch(`http://127.0.0.1:${port}/paas/caddy/ask?domain=evil.paas.mw.local`);
    assert.equal(denied.status, 403);

    // Simulate teardown removing active deployment
    activeDeployments.delete('app-alpha.paas.mw.local');
    const afterTeardown = await fetch(`http://127.0.0.1:${port}/paas/caddy/ask?domain=app-alpha.paas.mw.local`);
    assert.equal(afterTeardown.status, 403);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
