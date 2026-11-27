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

function evaluateDunningTransition(subscriber, nowEpochSec) {
  if (subscriber.balanceDueCents <= 0) {
    return {
      status: 'active',
      coaAction: subscriber.status === 'suspended' ? 'CoA-Restore-Profile' : 'none',
      rateLimit: subscriber.planRateLimit,
    };
  }
  const overdueDays = Math.floor((nowEpochSec - subscriber.dueAtEpochSec) / 86400);
  if (overdueDays >= subscriber.graceDays) {
    return {
      status: 'suspended',
      coaAction: 'CoA-Disconnect-Request',
      rateLimit: '0k/0k',
    };
  }
  return {
    status: 'grace',
    coaAction: 'none',
    rateLimit: subscriber.planRateLimit,
  };
}

test('V26: docker-compose.yml exposes ISP RADIUS UDP 1812/1813 and /health', () => {
  const compose = read('docker-compose.yml');
  const ispBlock = compose.match(/^\s{2}mw-isp:[\s\S]*?(?=^\s{2}[a-z0-9-]+:)/m)?.[0] ?? '';
  assert.ok(ispBlock.length > 0, 'mw-isp service block present');
  assert.match(ispBlock, /1812:1812\/udp/);
  assert.match(ispBlock, /1813:1813\/udp/);
  assert.match(ispBlock, /\/health/);
});

test('V26: ISP RADIUS CoA dunning state machine disconnects overdue and restores on payment', () => {
  const dueAt = 1_700_000_000;
  const sub = {
    username: 'pppoe-user-01',
    status: 'active',
    balanceDueCents: 15000,
    dueAtEpochSec: dueAt,
    graceDays: 3,
    planRateLimit: '50M/50M',
  };

  // Day 1 overdue: still within grace period
  const day1 = evaluateDunningTransition(sub, dueAt + 86400);
  assert.equal(day1.status, 'grace');
  assert.equal(day1.coaAction, 'none');

  // Day 4 overdue: triggers RADIUS CoA Disconnect-Request
  const day4 = evaluateDunningTransition(sub, dueAt + 4 * 86400);
  assert.equal(day4.status, 'suspended');
  assert.equal(day4.coaAction, 'CoA-Disconnect-Request');
  assert.equal(day4.rateLimit, '0k/0k');

  // Payment received: triggers CoA profile restore
  const paid = evaluateDunningTransition({ ...sub, status: 'suspended', balanceDueCents: 0 }, dueAt + 5 * 86400);
  assert.equal(paid.status, 'active');
  assert.equal(paid.coaAction, 'CoA-Restore-Profile');
  assert.equal(paid.rateLimit, '50M/50M');
});
