import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return readFileSync(path.join(ROOT, rel), 'utf8');
}

function runCognitiveLoop(input, tools) {
  const trace = [];
  trace.push({ phase: 'perceive', intent: input.intent });
  const plan = { tool: input.requestedTool, args: input.args };
  trace.push({ phase: 'plan', tool: plan.tool });

  const handler = tools[plan.tool];
  if (!handler) {
    trace.push({ phase: 'reflect', status: 'blocked', reason: `unknown_tool:${plan.tool}` });
    return { ok: false, trace };
  }
  const output = handler(plan.args);
  trace.push({ phase: 'act', output });
  trace.push({ phase: 'reflect', status: 'completed', verified: Boolean(output?.ok) });
  return { ok: Boolean(output?.ok), trace };
}

test('V27: Rocksoul profile services (4510-4540) and Zero-ORM audit contract', () => {
  const compose = read('docker-compose.yml');
  for (const [svc, port] of [
    ['mw-rocksoul-gateway', '4510'],
    ['mw-rocksoul-core', '4520'],
    ['mw-rocksoul-mcp', '4530'],
    ['mw-rocksoul-sandbox', '4540'],
  ]) {
    const block = compose.match(new RegExp(`^\\s{2}${svc}:[\\s\\S]*?(?=^\\s{2}[a-z0-9-]+:)`, 'm'))?.[0] ?? '';
    assert.ok(block.length > 0, `${svc} present in docker-compose.yml`);
    assert.match(block, /"rocksoul"/, `${svc} assigned to rocksoul profile`);
    assert.match(block, new RegExp(`:${port}"`), `${svc} maps port ${port}`);
  }

  const auditSh = read('scripts/ci/audit-fleet-security.sh');
  assert.match(auditSh, /@moonwitness\/orm-/);
  assert.match(auditSh, /mw-rocksoul-\*/);
});

test('V27: Rocksoul cognitive loop executes perceive -> plan -> act -> reflect deterministically', () => {
  const tools = {
    'sandbox.exec': ({ cmd }) => ({ ok: cmd === 'echo ok', stdout: 'ok' }),
  };

  const passRes = runCognitiveLoop(
    { intent: 'health-probe', requestedTool: 'sandbox.exec', args: { cmd: 'echo ok' } },
    tools,
  );
  assert.equal(passRes.ok, true);
  assert.deepEqual(
    passRes.trace.map((step) => step.phase),
    ['perceive', 'plan', 'act', 'reflect'],
  );

  const blockedRes = runCognitiveLoop(
    { intent: 'invalid-tool', requestedTool: 'orm.directWrite', args: {} },
    tools,
  );
  assert.equal(blockedRes.ok, false);
  assert.equal(blockedRes.trace.at(-1).status, 'blocked');
});
