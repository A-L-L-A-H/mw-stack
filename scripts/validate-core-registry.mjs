#!/usr/bin/env node
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CORE_DIR = path.resolve(__dirname, '../../mw-core');

const reposPath = path.join(CORE_DIR, 'registry', 'repositories.json');
const servicesPath = path.join(CORE_DIR, 'registry', 'services.json');

if (!existsSync(reposPath)) {
  console.error(`ERROR: Missing ${reposPath}`);
  process.exit(1);
}
if (!existsSync(servicesPath)) {
  console.error(`ERROR: Missing ${servicesPath}`);
  process.exit(1);
}

const reposData = JSON.parse(readFileSync(reposPath, 'utf8'));
const servicesData = JSON.parse(readFileSync(servicesPath, 'utf8'));

const VALID_PROFILES = new Set(['lite', 'id', 'ops', 'isp', 'saas', 'epistemic', 'portal', 'studio', 'mobile', 'rocksoul', 'full']);

const errors = [];

// 1. Validate Non-Operational Check: mw-core must NOT contain operational folders
const FORBIDDEN_DIRS = ['scripts', 'docker', 'compose'];
for (const forbidden of FORBIDDEN_DIRS) {
  if (existsSync(path.join(CORE_DIR, forbidden))) {
    errors.push(`Non-operational violation: mw-core must not contain '${forbidden}/' directory.`);
  }
}

// 2. Validate Repositories
const repoNames = new Set();
if (!Array.isArray(reposData.repositories)) {
  errors.push("repositories.json must contain a 'repositories' array.");
} else {
  for (const repo of reposData.repositories) {
    if (!repo.name) {
      errors.push("Repository missing 'name'.");
      continue;
    }
    if (repoNames.has(repo.name)) {
      errors.push(`Duplicate repository name: ${repo.name}`);
    }
    repoNames.add(repo.name);

    if (repo.profile && !VALID_PROFILES.has(repo.profile)) {
      errors.push(`Invalid profile '${repo.profile}' in repository ${repo.name}`);
    }
  }
}

// 3. Validate Services
const serviceNames = new Set();
const portsUsed = new Map();

if (!servicesData.services || typeof servicesData.services !== 'object') {
  errors.push("services.json must contain a 'services' object.");
} else {
  for (const [key, svc] of Object.entries(servicesData.services)) {
    if (key !== svc.name) {
      errors.push(`Service key '${key}' does not match service name '${svc.name}'.`);
    }
    if (serviceNames.has(svc.name)) {
      errors.push(`Duplicate service name: ${svc.name}`);
    }
    serviceNames.add(svc.name);

    if (svc.profile && !VALID_PROFILES.has(svc.profile)) {
      errors.push(`Invalid profile '${svc.profile}' in service ${svc.name}`);
    }

    if (svc.port !== null && svc.port !== undefined) {
      if (typeof svc.port !== 'number') {
        errors.push(`Invalid port type for ${svc.name}: expected number or null, got ${typeof svc.port}`);
      } else {
        if (portsUsed.has(svc.port)) {
          errors.push(`Port collision: port ${svc.port} used by both ${portsUsed.get(svc.port)} and ${svc.name}`);
        } else {
          portsUsed.set(svc.port, svc.name);
        }
      }
    }

    if (svc.healthEndpoint !== null && svc.healthEndpoint !== undefined) {
      try {
        new URL(svc.healthEndpoint);
      } catch (err) {
        errors.push(`Invalid healthEndpoint URL '${svc.healthEndpoint}' for ${svc.name}`);
      }
    }

    if (!svc.endpoints || typeof svc.endpoints !== 'object') {
      errors.push(`Service ${svc.name} missing 'endpoints' map.`);
    }
  }
}

console.log(`Validated ${repoNames.size} repositories and ${serviceNames.size} services.`);

if (errors.length > 0) {
  console.error("Core Registry Validation FAILED with errors:");
  for (const err of errors) {
    console.error(` - ${err}`);
  }
  process.exit(1);
}

console.log("Core Registry Validation PASSED: Unique names, unique ports, valid profiles, valid health URLs, and strictly non-operational.");
process.exit(0);
