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

function signJwtRs256(payload, privateKey, kid) {
  const header = { alg: 'RS256', typ: 'JWT', kid };
  const encHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
  const encPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signingInput = `${encHeader}.${encPayload}`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(signingInput), privateKey).toString('base64url');
  return `${signingInput}.${sig}`;
}

function verifyJwtWithJwks(token, jwks) {
  const parts = token.split('.');
  assert.equal(parts.length, 3, 'JWT must have 3 dot-separated segments');
  const [encHeader, encPayload, encSig] = parts;
  const header = JSON.parse(Buffer.from(encHeader, 'base64url').toString('utf8'));
  const jwk = jwks.keys.find((k) => k.kid === header.kid && k.use === 'sig');
  if (!jwk) {
    throw new Error(`Unknown kid: ${header.kid}`);
  }
  const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const ok = crypto.verify(
    'RSA-SHA256',
    Buffer.from(`${encHeader}.${encPayload}`),
    publicKey,
    Buffer.from(encSig, 'base64url'),
  );
  if (!ok) {
    throw new Error('Invalid JWT signature');
  }
  return JSON.parse(Buffer.from(encPayload, 'base64url').toString('utf8'));
}

test('V24: docker-compose.yml wires mw-rid JWKS endpoint to downstream services', () => {
  const compose = read('docker-compose.yml');
  assert.match(compose, /^\s{2}mw-rid:/m, 'mw-rid service defined');
  assert.match(compose, /MW_RID_JWKS_URL:\s*"http:\/\/mw-rid:4480\/jwks"/);
});

test('V24: JWKS contract verifies RS256 tokens across active and rotated kids', () => {
  const k1 = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const k2 = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

  const jwk1 = { ...k1.publicKey.export({ format: 'jwk' }), kid: 'rid-2026-10', use: 'sig', alg: 'RS256' };
  const jwk2 = { ...k2.publicKey.export({ format: 'jwk' }), kid: 'rid-2026-11', use: 'sig', alg: 'RS256' };
  const jwks = { keys: [jwk1, jwk2] };

  const tokenOld = signJwtRs256({ sub: 'tenant-1', iss: 'http://mw-rid:4480', aud: 'mw-isp' }, k1.privateKey, 'rid-2026-10');
  const tokenNew = signJwtRs256({ sub: 'tenant-1', iss: 'http://mw-rid:4480', aud: 'mw-mission' }, k2.privateKey, 'rid-2026-11');

  assert.equal(verifyJwtWithJwks(tokenOld, jwks).aud, 'mw-isp');
  assert.equal(verifyJwtWithJwks(tokenNew, jwks).aud, 'mw-mission');

  const forged = `${tokenNew.slice(0, -4)}AAAA`;
  assert.throws(() => verifyJwtWithJwks(forged, jwks), /Invalid JWT signature/);

  const unknownKid = signJwtRs256({ sub: 'tenant-1' }, k2.privateKey, 'rid-revoked');
  assert.throws(() => verifyJwtWithJwks(unknownKid, jwks), /Unknown kid/);
});
