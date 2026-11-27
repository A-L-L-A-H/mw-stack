import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function findBash() {
  const candidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
    '/bin/bash',
    '/usr/bin/bash',
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return 'bash';
}

test('V31: mwctl rotate-keys supports --dry-run, atomic dual-key rotation, backup checksum, and --rollback', () => {
  const bash = findBash();
  const tmpDir = mkdtempSync(path.join(os.tmpdir(), 'mw-rotate-keys-'));
  const envFile = path.join(tmpDir, '.env');
  const backupDir = path.join(tmpDir, 'backups');

  try {
    const initialEnv = [
      'MW_API_SECRET=initial-api-secret-0001',
      'MW_JWT_SECRET=initial-jwt-secret-0002',
      'MW_ENCRYPTION_KEY=initial-enc-key-0003',
      '',
    ].join('\n');
    writeFileSync(envFile, initialEnv, 'utf8');

    const toPosix = (p) => p.replace(/\\/g, '/');
    const mwctlPath = toPosix(path.join(ROOT, 'mwctl'));

    // 1. Dry-run must not modify .env
    const dryOut = execFileSync(
      bash,
      [mwctlPath, 'rotate-keys', '--env-file', toPosix(envFile), '--backup-dir', toPosix(backupDir), '--dry-run'],
      { encoding: 'utf8' },
    );
    assert.match(dryOut, /\[dry-run\]/);
    assert.equal(readFileSync(envFile, 'utf8'), initialEnv);

    // 2. Real rotation with --no-restart
    const rotOut = execFileSync(
      bash,
      [mwctlPath, 'rotate-keys', '--env-file', toPosix(envFile), '--backup-dir', toPosix(backupDir), '--no-restart'],
      { encoding: 'utf8' },
    );
    assert.match(rotOut, /Rotated 3 key\(s\)/);

    const rotatedEnv = readFileSync(envFile, 'utf8');
    assert.match(rotatedEnv, /MW_API_SECRET_PREVIOUS=initial-api-secret-0001/);
    assert.match(rotatedEnv, /MW_JWT_SECRET_PREVIOUS=initial-jwt-secret-0002/);
    assert.match(rotatedEnv, /MW_ENCRYPTION_KEY_PREVIOUS=initial-enc-key-0003/);
    assert.doesNotMatch(rotatedEnv, /^MW_API_SECRET=initial-api-secret-0001$/m);

    const backups = readdirSync(backupDir).filter((f) => f.endsWith('.bak'));
    assert.equal(backups.length, 1, 'timestamped .bak created');
    const bakPath = path.join(backupDir, backups[0]);
    assert.ok(existsSync(`${bakPath}.sha256`), 'backup .sha256 checksum created');

    // 3. Rollback restores exact initial .env
    const rbOut = execFileSync(
      bash,
      [mwctlPath, 'rotate-keys', '--rollback', toPosix(bakPath), '--env-file', toPosix(envFile), '--no-restart'],
      { encoding: 'utf8' },
    );
    assert.match(rbOut, /Rolled back/);
    assert.equal(readFileSync(envFile, 'utf8'), initialEnv);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('V36: scripts/audit-vulns-zero-card.sh supports --dry-run and Trivy + Gitleaks zero-card flow', () => {
  const bash = findBash();
  const scriptPath = path.join(ROOT, 'scripts', 'ci', 'audit-vulns-zero-card.sh').replace(/\\/g, '/');
  const out = execFileSync(bash, [scriptPath, '--dry-run'], { encoding: 'utf8' });
  assert.match(out, /\[dry-run\] Gitleaks report:/);
  assert.match(out, /\[dry-run\] Trivy FS report:/);
});
