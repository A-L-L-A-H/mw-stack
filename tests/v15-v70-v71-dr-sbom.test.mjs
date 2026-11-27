import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  scanRepositories,
  generateCycloneDxSbom,
  generateAttestation,
  runCli,
} from '../scripts/generate-sbom-attestation.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return readFileSync(path.join(ROOT, rel), 'utf8');
}

function toPosixPath(p) {
  return p.replace(/\\/g, '/');
}

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

const BASH = findBash();

test('V15: backup-rclone-321.sh enforces 3-2-1 rclone crypt workflow and passes --dry-run', () => {
  const script = read('scripts/backup-rclone-321.sh');
  assert.match(script, /rclone copy/);
  assert.match(script, /RCLONE_CRYPT_REMOTE/);
  assert.match(script, /--dry-run/);
  assert.match(script, /sha256sum/);

  const tmp = mkdtempSync(path.join(os.tmpdir(), 'mw-v15-'));
  try {
    const srcDir = path.join(tmp, 'src');
    const localDir = path.join(tmp, 'local');
    const manifestPath = path.join(tmp, 'manifest.sha256');
    mkdirSync(srcDir, { recursive: true });
    writeFileSync(path.join(srcDir, 'state.json'), '{"ok":true}\n', 'utf8');

    const out = execFileSync(
      BASH,
      [
        toPosixPath(path.join(ROOT, 'scripts/backup-rclone-321.sh')),
        '--dry-run',
        '--source',
        toPosixPath(srcDir),
        '--local-dir',
        toPosixPath(localDir),
        '--manifest',
        toPosixPath(manifestPath),
      ],
      { encoding: 'utf8' },
    );

    assert.match(out, /Verification PASS/);
    assert.ok(existsSync(manifestPath), 'Checksum manifest must be created');
    const manifestContent = readFileSync(manifestPath, 'utf8');
    assert.match(manifestContent, /[a-f0-9]{64}\s+/);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});

test('V70: dr-gameday-drill.sh executes local sandbox restore & tamper verification without VPS credentials', () => {
  const script = read('scripts/dr-gameday-drill.sh');
  assert.match(script, /--dry-run/);
  assert.match(script, /sha256sum -c/);
  assert.match(script, /tamperRejected/);

  const tmp = mkdtempSync(path.join(os.tmpdir(), 'mw-v70-'));
  try {
    const reportPath = path.join(tmp, 'dr-report.json');
    const out = execFileSync(
      BASH,
      [
        toPosixPath(path.join(ROOT, 'scripts/dr-gameday-drill.sh')),
        '--dry-run',
        '--report',
        toPosixPath(reportPath),
      ],
      { encoding: 'utf8' },
    );

    const parsedOut = JSON.parse(out);
    assert.equal(parsedOut.status, 'PASS');
    assert.equal(parsedOut.dryRun, true);
    assert.equal(parsedOut.checks.bootstrap, true);
    assert.equal(parsedOut.checks.checksumVerified, true);
    assert.equal(parsedOut.checks.restoreParity, true);
    assert.equal(parsedOut.checks.tamperRejected, true);

    assert.ok(existsSync(reportPath), 'DR report file must be written');
    const parsedFile = JSON.parse(readFileSync(reportPath, 'utf8'));
    assert.equal(parsedFile.status, 'PASS');
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});

test('V71: generate-sbom-attestation.mjs produces CycloneDX 1.5 SBOM + SHA-256 attestation across ecosystems', () => {
  const tmp = mkdtempSync(path.join(os.tmpdir(), 'mw-v71-'));
  try {
    const reposRoot = path.join(tmp, 'repos');
    const outDir = path.join(tmp, 'out');
    mkdirSync(path.join(reposRoot, 'mw-alpha'), { recursive: true });
    mkdirSync(path.join(reposRoot, 'mw-beta'), { recursive: true });
    mkdirSync(path.join(reposRoot, 'mw-gamma'), { recursive: true });
    mkdirSync(path.join(reposRoot, 'mw-delta'), { recursive: true });

    writeFileSync(
      path.join(reposRoot, 'mw-alpha', 'package.json'),
      JSON.stringify({
        name: 'mw-alpha',
        dependencies: { fastify: '^5.0.0' },
        devDependencies: { typescript: '~5.6.0' },
      }),
      'utf8',
    );
    writeFileSync(
      path.join(reposRoot, 'mw-beta', 'go.mod'),
      'module github.com/moonwitness/mw-beta\n\ngo 1.23\n\nrequire (\n\tgithub.com/gin-gonic/gin v1.10.0\n)\n',
      'utf8',
    );
    writeFileSync(
      path.join(reposRoot, 'mw-gamma', 'Cargo.toml'),
      '[package]\nname = "mw-gamma"\nversion = "0.1.0"\n\n[dependencies]\nserde = "1.0.210"\ntokio = { version = "1.40.0", features = ["full"] }\n',
      'utf8',
    );
    writeFileSync(
      path.join(reposRoot, 'mw-delta', 'pyproject.toml'),
      '[project]\nname = "mw-delta"\ndependencies = [\n  "fastapi>=0.115.0",\n  "pydantic==2.9.0",\n]\n',
      'utf8',
    );

    const scan = scanRepositories(reposRoot);
    assert.deepEqual(scan.repositoriesScanned, ['mw-alpha', 'mw-beta', 'mw-delta', 'mw-gamma']);
    assert.equal(scan.manifests.length, 4);

    const sbom = generateCycloneDxSbom(scan);
    assert.equal(sbom.bomFormat, 'CycloneDX');
    assert.equal(sbom.specVersion, '1.5');
    assert.match(sbom.serialNumber, /^urn:uuid:/);

    const purls = new Set(sbom.components.map((c) => c.purl));
    assert.ok(purls.has('pkg:npm/fastify@5.0.0'));
    assert.ok(purls.has('pkg:golang/github.com/gin-gonic/gin@v1.10.0'));
    assert.ok(purls.has('pkg:cargo/serde@1.0.210'));
    assert.ok(purls.has('pkg:pypi/fastapi@0.115.0'));

    const sbomJson = `${JSON.stringify(sbom, null, 2)}\n`;
    const attestation = generateAttestation(sbomJson, scan, reposRoot);
    const expectedSha = crypto.createHash('sha256').update(sbomJson).digest('hex');
    assert.equal(attestation.subject[0].digest.sha256, expectedSha);

    // End-to-end CLI check
    const cliResult = runCli(['--root', reposRoot, '--out-dir', outDir]);
    assert.ok(existsSync(cliResult.sbomPath));
    assert.ok(existsSync(cliResult.attestationPath));
    const writtenSbom = readFileSync(cliResult.sbomPath, 'utf8');
    const writtenAttest = JSON.parse(readFileSync(cliResult.attestationPath, 'utf8'));
    assert.equal(
      crypto.createHash('sha256').update(writtenSbom).digest('hex'),
      writtenAttest.subject[0].digest.sha256,
    );
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
