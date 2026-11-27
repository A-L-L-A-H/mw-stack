import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return readFileSync(path.join(ROOT, rel), 'utf8');
}

function encryptBackup(plaintextBuf, passphrase) {
  const salt = crypto.randomBytes(16);
  const keyIv = crypto.pbkdf2Sync(passphrase, salt, 100_000, 48, 'sha256');
  const key = keyIv.subarray(0, 32);
  const iv = keyIv.subarray(32, 48);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  const ciphertext = Buffer.concat([salt, cipher.update(plaintextBuf), cipher.final()]);
  const sha256 = crypto.createHash('sha256').update(ciphertext).digest('hex');
  return { ciphertext, sha256 };
}

function verifyAndDecryptBackup(ciphertext, expectedSha256, passphrase) {
  const actualSha256 = crypto.createHash('sha256').update(ciphertext).digest('hex');
  if (actualSha256 !== expectedSha256) {
    throw new Error(`Checksum mismatch: expected ${expectedSha256}, got ${actualSha256}`);
  }
  const salt = ciphertext.subarray(0, 16);
  const body = ciphertext.subarray(16);
  const keyIv = crypto.pbkdf2Sync(passphrase, salt, 100_000, 48, 'sha256');
  const key = keyIv.subarray(0, 32);
  const iv = keyIv.subarray(32, 48);
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  return Buffer.concat([decipher.update(body), decipher.final()]);
}

test('V28: backup-business-vps.sh and restore-business-vps.sh enforce AES-256-CBC + SHA-256 verification', () => {
  const backupSh = read('scripts/ops/backup-business-vps.sh');
  assert.match(backupSh, /pg_dump/);
  assert.match(backupSh, /openssl enc -aes-256-cbc -pbkdf2/);
  assert.match(backupSh, /sha256sum "\$ARCHIVE_ENC" > "\$SUM_FILE"/);

  const restoreSh = read('scripts/ops/restore-business-vps.sh');
  assert.match(restoreSh, /sha256sum -c "\$\{ARCHIVE\}\.sha256"/);
  assert.match(restoreSh, /openssl enc -d -aes-256-cbc -pbkdf2/);
  assert.match(restoreSh, /--verify-only/);
});

test('V28: chaos backup-restore round-trip passes on intact payload and rejects 1-byte bit-flip', () => {
  const passphrase = 'test-sovereign-backup-key';
  const payload = Buffer.from(
    '-- SQLite/Postgres synthetic dump\nCREATE TABLE invoices (id INT PRIMARY KEY, total INT);\nINSERT INTO invoices VALUES (1, 9900);\n',
    'utf8',
  );

  const { ciphertext, sha256 } = encryptBackup(payload, passphrase);
  const restored = verifyAndDecryptBackup(ciphertext, sha256, passphrase);
  assert.deepEqual(restored, payload);

  // Chaos injection: flip 1 byte in encrypted archive
  const corrupted = Buffer.from(ciphertext);
  corrupted[corrupted.length - 1] ^= 0xff;
  assert.throws(() => verifyAndDecryptBackup(corrupted, sha256, passphrase), /Checksum mismatch/);
});
