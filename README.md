# mw-stack — One-command installer and fleet orchestrator for the MoonWitness stack.

**Repository:** [`A-L-L-A-H/mw-stack`](https://github.com/A-L-L-A-H/mw-stack) · **Stack:** Docker Compose v2 · Shell · PowerShell

## What it does

Provides composable deployment profiles, the mwctl operator CLI, Caddy/cloudflared edge routing, and fleet verification.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.sh | bash
```

## Verify

```bash
docker compose config -q
bash -n install.sh
bash -n mwctl
```

## Configuration

- **Port:** Many (see profiles)
- **Key configuration:** MW_PROFILE · MW_DOMAIN · .env

```bash
mwctl up <profile>
mwctl status
mwctl verify
```

## Notes

Profiles include lite, id, ops, saas, isp, epistemic, portal, studio, rocksoul, tunnel, proxy, and full.
