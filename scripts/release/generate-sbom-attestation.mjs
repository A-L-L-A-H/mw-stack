#!/usr/bin/env node
/**
 * V71: CycloneDX 1.5 JSON SBOM + SHA-256 Attestation Manifest Generator
 * Scans sibling `mw-*` repositories for package.json, go.mod, Cargo.toml, and pyproject.toml.
 */

import crypto from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = path.resolve(__dirname, '../../..');
const DEFAULT_OUT_DIR = path.resolve(__dirname, '../../.sbom');

function sha256Hex(content) {
  return crypto.createHash('sha256').update(content).digest('hex');
}

function cleanVersion(raw) {
  return String(raw || '0.0.0')
    .trim()
    .replace(/^[\^~>=<!\s]+/, '')
    .split(/[\s,]+/)[0] || '0.0.0';
}

export function parsePackageJson(filePath, repoName) {
  const raw = readFileSync(filePath, 'utf8');
  const pkg = JSON.parse(raw);
  const components = [];
  const sections = [
    ['dependencies', 'required'],
    ['devDependencies', 'optional'],
  ];

  for (const [section, scope] of sections) {
    const deps = pkg[section];
    if (!deps || typeof deps !== 'object') continue;
    for (const [name, versionRange] of Object.entries(deps)) {
      const version = cleanVersion(versionRange);
      const purlName = name.startsWith('@')
        ? `%40${name.slice(1)}`
        : name;
      components.push({
        type: 'library',
        name,
        version,
        scope,
        purl: `pkg:npm/${purlName}@${version}`,
        properties: [
          { name: 'mw:repository', value: repoName },
          { name: 'mw:manifest', value: 'package.json' },
          { name: 'mw:ecosystem', value: 'npm' },
        ],
      });
    }
  }

  return {
    manifest: {
      repository: repoName,
      file: 'package.json',
      sha256: sha256Hex(raw),
    },
    components,
  };
}

export function parseGoMod(filePath, repoName) {
  const raw = readFileSync(filePath, 'utf8');
  const components = [];
  const lines = raw.split(/\r?\n/);
  let inRequireBlock = false;

  for (const rawLine of lines) {
    const line = rawLine.replace(/\/\/.*$/, '').trim();
    if (!line) continue;
    if (line.startsWith('require (')) {
      inRequireBlock = true;
      continue;
    }
    if (inRequireBlock && line === ')') {
      inRequireBlock = false;
      continue;
    }

    let match = null;
    if (inRequireBlock) {
      match = line.match(/^([^\s]+)\s+([^\s]+)/);
    } else if (line.startsWith('require ')) {
      match = line.slice('require '.length).trim().match(/^([^\s]+)\s+([^\s]+)/);
    }

    if (match) {
      const [, modPath, version] = match;
      components.push({
        type: 'library',
        name: modPath,
        version,
        scope: 'required',
        purl: `pkg:golang/${modPath}@${version}`,
        properties: [
          { name: 'mw:repository', value: repoName },
          { name: 'mw:manifest', value: 'go.mod' },
          { name: 'mw:ecosystem', value: 'golang' },
        ],
      });
    }
  }

  return {
    manifest: {
      repository: repoName,
      file: 'go.mod',
      sha256: sha256Hex(raw),
    },
    components,
  };
}

export function parseCargoToml(filePath, repoName) {
  const raw = readFileSync(filePath, 'utf8');
  const components = [];
  const lines = raw.split(/\r?\n/);
  let inDeps = false;
  let scope = 'required';

  for (const rawLine of lines) {
    const line = rawLine.replace(/#.*$/, '').trim();
    if (!line) continue;
    if (line.startsWith('[')) {
      inDeps = line === '[dependencies]' || line === '[dev-dependencies]';
      scope = line === '[dev-dependencies]' ? 'optional' : 'required';
      continue;
    }
    if (!inDeps) continue;

    const eqIdx = line.indexOf('=');
    if (eqIdx === -1) continue;
    const name = line.slice(0, eqIdx).trim().replace(/^["']|["']$/g, '');
    const rhs = line.slice(eqIdx + 1).trim();
    let version = '0.0.0';
    const simpleMatch = rhs.match(/^["']([^"']+)["']/);
    const inlineMatch = rhs.match(/version\s*=\s*["']([^"']+)["']/);
    if (simpleMatch) {
      version = cleanVersion(simpleMatch[1]);
    } else if (inlineMatch) {
      version = cleanVersion(inlineMatch[1]);
    }

    if (name) {
      components.push({
        type: 'library',
        name,
        version,
        scope,
        purl: `pkg:cargo/${name}@${version}`,
        properties: [
          { name: 'mw:repository', value: repoName },
          { name: 'mw:manifest', value: 'Cargo.toml' },
          { name: 'mw:ecosystem', value: 'cargo' },
        ],
      });
    }
  }

  return {
    manifest: {
      repository: repoName,
      file: 'Cargo.toml',
      sha256: sha256Hex(raw),
    },
    components,
  };
}

export function parsePyprojectToml(filePath, repoName) {
  const raw = readFileSync(filePath, 'utf8');
  const components = [];
  const depsArrayMatch = raw.match(/dependencies\s*=\s*\[([\s\S]*?)\]/m);

  if (depsArrayMatch) {
    const entries = depsArrayMatch[1].match(/["']([^"']+)["']/g) || [];
    for (const quoted of entries) {
      const spec = quoted.slice(1, -1).trim();
      const m = spec.match(/^([A-Za-z0-9_.-]+)(?:\[[^\]]+\])?\s*([<>=!~]+.*)?$/);
      if (!m) continue;
      const name = m[1];
      const version = cleanVersion(m[2] || '0.0.0');
      components.push({
        type: 'library',
        name,
        version,
        scope: 'required',
        purl: `pkg:pypi/${name.toLowerCase()}@${version}`,
        properties: [
          { name: 'mw:repository', value: repoName },
          { name: 'mw:manifest', value: 'pyproject.toml' },
          { name: 'mw:ecosystem', value: 'pypi' },
        ],
      });
    }
  }

  return {
    manifest: {
      repository: repoName,
      file: 'pyproject.toml',
      sha256: sha256Hex(raw),
    },
    components,
  };
}

export function scanRepositories(rootDir, repoFilter = null) {
  if (!existsSync(rootDir)) {
    throw new Error(`Root directory does not exist: ${rootDir}`);
  }

  const entries = readdirSync(rootDir)
    .filter((name) => name.startsWith('mw-'))
    .filter((name) => !repoFilter || repoFilter.has(name))
    .filter((name) => {
      try {
        return statSync(path.join(rootDir, name)).isDirectory();
      } catch {
        return false;
      }
    })
    .sort();

  const components = [];
  const manifests = [];

  const parsers = [
    ['package.json', parsePackageJson],
    ['go.mod', parseGoMod],
    ['Cargo.toml', parseCargoToml],
    ['pyproject.toml', parsePyprojectToml],
  ];

  for (const repoName of entries) {
    const repoPath = path.join(rootDir, repoName);
    for (const [filename, parser] of parsers) {
      const fullPath = path.join(repoPath, filename);
      if (!existsSync(fullPath)) continue;
      const parsed = parser(fullPath, repoName);
      manifests.push(parsed.manifest);
      components.push(...parsed.components);
    }
  }

  return {
    repositoriesScanned: entries,
    manifests,
    components,
  };
}

export function generateCycloneDxSbom(scanResult, timestamp = new Date().toISOString()) {
  return {
    bomFormat: 'CycloneDX',
    specVersion: '1.5',
    serialNumber: `urn:uuid:${crypto.randomUUID()}`,
    version: 1,
    metadata: {
      timestamp,
      tools: {
        components: [
          {
            type: 'application',
            name: 'mw-stack-sbom-attestation',
            version: '1.0.0',
          },
        ],
      },
      component: {
        type: 'application',
        name: 'moonwitness-fleet',
        version: '1.0.0',
      },
    },
    components: scanResult.components,
  };
}

export function generateAttestation(sbomJsonString, scanResult, rootDir, timestamp = new Date().toISOString()) {
  const sbomDigest = sha256Hex(sbomJsonString);
  return {
    _type: 'https://in-toto.io/Statement/v1',
    subject: [
      {
        name: 'sbom.cdx.json',
        digest: {
          sha256: sbomDigest,
        },
      },
    ],
    predicateType: 'https://cyclonedx.org/bom/v1.5',
    predicate: {
      generatedAt: timestamp,
      rootDir,
      repositoriesScanned: scanResult.repositoriesScanned,
      componentCount: scanResult.components.length,
      manifestDigests: scanResult.manifests,
    },
  };
}

export function runCli(argv = process.argv.slice(2)) {
  let rootDir = DEFAULT_ROOT;
  let outDir = DEFAULT_OUT_DIR;
  let repoFilter = null;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--root' && argv[i + 1]) {
      rootDir = path.resolve(argv[++i]);
    } else if (arg === '--out-dir' && argv[i + 1]) {
      outDir = path.resolve(argv[++i]);
    } else if (arg === '--repos' && argv[i + 1]) {
      repoFilter = new Set(argv[++i].split(',').map((s) => s.trim()).filter(Boolean));
    } else if (arg === '--help' || arg === '-h') {
      console.log('Usage: generate-sbom-attestation.mjs [--root <dir>] [--out-dir <dir>] [--repos <a,b>]');
      return null;
    }
  }

  const timestamp = new Date().toISOString();
  const scanResult = scanRepositories(rootDir, repoFilter);
  const sbom = generateCycloneDxSbom(scanResult, timestamp);
  const sbomJson = `${JSON.stringify(sbom, null, 2)}\n`;
  const attestation = generateAttestation(sbomJson, scanResult, rootDir, timestamp);
  const attestationJson = `${JSON.stringify(attestation, null, 2)}\n`;

  mkdirSync(outDir, { recursive: true });
  const sbomPath = path.join(outDir, 'sbom.cdx.json');
  const attestationPath = path.join(outDir, 'sbom-attestation.json');
  writeFileSync(sbomPath, sbomJson, 'utf8');
  writeFileSync(attestationPath, attestationJson, 'utf8');

  console.log(
    JSON.stringify({
      status: 'PASS',
      sbomPath,
      attestationPath,
      repositoriesScanned: scanResult.repositoriesScanned.length,
      componentCount: scanResult.components.length,
      sbomSha256: attestation.subject[0].digest.sha256,
    }),
  );

  return { sbomPath, attestationPath, sbom, attestation };
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  runCli();
}
