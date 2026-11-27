import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return readFileSync(path.join(ROOT, rel), 'utf8');
}

test('V08: deploy-remote-vps.sh uses tar|ssh bundle upload without raw.githubusercontent.com fetch', () => {
  const src = read('scripts/ops/deploy-remote-vps.sh');
  assert.doesNotMatch(src, /raw\.githubusercontent\.com/);
  assert.match(src, /tar\s+-C\s+"\$LOCAL_STACK_DIR"[\s\S]*\|/);
  assert.match(src, /--port\)/);
  assert.match(src, /--key\)/);
  assert.match(src, /--skip-sync/);
});

test('V09: docker-compose.yml configures business profile, JWKS wiring, rocksoul ports, and /health checks', () => {
  const compose = read('docker-compose.yml');

  // mw-mylove must belong to business profile
  const myloveBlock = compose.match(/^\s{2}mw-mylove:[\s\S]*?(?=^\s{2}[a-z0-9-]+:)/m)?.[0] ?? '';
  assert.ok(myloveBlock.length > 0, 'mw-mylove block present');
  assert.match(myloveBlock, /profiles:\s*\[[^\]]*"business"/);

  // mw-isp and mw-mission must wire MW_RID_JWKS_URL
  const ispBlock = compose.match(/^\s{2}mw-isp:[\s\S]*?(?=^\s{2}[a-z0-9-]+:)/m)?.[0] ?? '';
  const missionBlock = compose.match(/^\s{2}mw-mission:[\s\S]*?(?=^\s{2}[a-z0-9-]+:)/m)?.[0] ?? '';
  assert.match(ispBlock, /MW_RID_JWKS_URL:\s*"http:\/\/mw-rid:4480\/jwks"/);
  assert.match(missionBlock, /MW_RID_JWKS_URL:\s*"http:\/\/mw-rid:4480\/jwks"/);

  // rocksoul profile ports 4510-4540
  for (const [svc, port] of [
    ['mw-rocksoul-gateway', '4510'],
    ['mw-rocksoul-core', '4520'],
    ['mw-rocksoul-mcp', '4530'],
    ['mw-rocksoul-sandbox', '4540'],
  ]) {
    const block = compose.match(new RegExp(`^\\s{2}${svc}:[\\s\\S]*?(?=^\\s{2}[a-z0-9-]+:)`, 'm'))?.[0] ?? '';
    assert.match(block, /profiles:\s*\[[^\]]*"rocksoul"/, `${svc} has rocksoul profile`);
    assert.match(block, new RegExp(`:${port}"`), `${svc} exposes ${port}`);
  }

  // Standardized /health checks on core services
  for (const svc of ['mw-echo', 'mw-rid', 'mw-lab', 'mw-mission', 'mw-cp', 'mw-isp', 'mw-mylove']) {
    const block = compose.match(new RegExp(`^\\s{2}${svc}:[\\s\\S]*?(?=^\\s{2}[a-z0-9-]+:)`, 'm'))?.[0] ?? '';
    assert.match(block, /healthcheck:/, `${svc} has healthcheck`);
    assert.match(block, /\/health/, `${svc} probes /health`);
  }
});

test('V10: docker-compose.proxy.yml isolates docker socket via docker-socket-proxy for mw-cp', () => {
  assert.ok(existsSync(path.join(ROOT, 'docker-compose.proxy.yml')));
  const proxy = read('docker-compose.proxy.yml');
  assert.match(proxy, /tecnativa\/docker-socket-proxy/);
  assert.match(proxy, /CONTAINERS:\s*"1"/);
  assert.match(proxy, /IMAGES:\s*"1"/);
  assert.match(proxy, /NETWORKS:\s*"1"/);
  assert.match(proxy, /VOLUMES:\s*"1"/);
  assert.match(proxy, /DOCKER_HOST:\s*"tcp:\/\/docker-socket-proxy:2375"/);

  const base = read('docker-compose.yml');
  const cpBlock = base.match(/^\s{2}mw-cp:[\s\S]*?(?=^\s{2}[a-z0-9-]+:)/m)?.[0] ?? '';
  assert.doesNotMatch(cpBlock, /docker\.sock/, 'mw-cp must not mount raw docker.sock');
});

test('V11: Caddyfile.template parameterizes MW_PORTAL_DOMAIN and preserves on_demand_tls ask', () => {
  const caddy = read('Caddyfile.template');
  assert.match(caddy, /\{\$MW_PORTAL_DOMAIN:a-l-l-a-h\.com\}/);
  assert.match(caddy, /\*\.paas\.\{\$MW_DOMAIN:mw\.local\}/);
  assert.match(caddy, /ask\s+http:\/\/mw-cp:4440\/paas\/caddy\/ask/);
  assert.doesNotMatch(caddy, /^a-l-l-a-h\.com\s*\{/m);
});

test('V12: install-business-vps.sh installs mw-ww-cli and schedules 02:30 daily sweep cron', () => {
  const installer = read('scripts/ops/install-business-vps.sh');
  assert.match(installer, /\/usr\/local\/bin\/mw-ww-cli/);
  assert.match(installer, /30 2 \* \* \* root/);
  assert.match(installer, /--clean-safe --apply/);
  assert.match(installer, /2097152/);
  assert.match(installer, /NTFY_TOPIC_URL/);
});

test('V13: mwctl supports save-images, load-images tar-pipe, and optional GHCR_TOKEN login', () => {
  const mwctl = read('mwctl');
  assert.match(mwctl, /save-images\)/);
  assert.match(mwctl, /load-images\)/);
  assert.match(mwctl, /docker save/);
  assert.match(mwctl, /docker load/);
  assert.match(mwctl, /GHCR_TOKEN/);
  assert.match(mwctl, /--password-stdin/);
});
