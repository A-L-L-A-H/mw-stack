# mw-stack — MoonWitness 1-Command VPS Deployment & Sovereign Fleet Orchestrator

Single-entry installer, `mwctl` operator CLI, and composable Docker Compose v2 fleet orchestrator for the MoonWitness sovereign stack.

## 1-Line Quick Start

### Linux VPS (Docker + Compose v2 + `mwctl`)
```bash
curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.sh | bash
```

Non-interactive profile selection:
```bash
curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.sh | MW_PROFILE=ops bash
```

### Windows PowerShell
Standalone `mw-echo.exe`:
```powershell
irm https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.ps1 | iex
```

Docker fleet mode:
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.ps1))) -Mode docker -Profile ops
```

## Composable Profiles

| Profile | Services | Exposed Ports |
| :--- | :--- | :--- |
| `lite` | `mw-echo` | `:4310` |
| `id` | `mw-rid` (Sovereign OIDC Identity Provider) | `:4480` |
| `ops` | `mw-echo`, `mw-rid`, `mw-lab`, `mw-mission`, `mw-cp` | `:4310`, `:4480`, `:4400`, `:4410`, `:4440` |
| `saas` | `postgres`, `mw-rid`, `mw-dock`, `mw-design`, `mw-board` | `:4480`, `:3000`, `:8080`, `:3001` |
| `isp` | `mw-isp` | `:8091`, `1812/udp`, `1813/udp` |
| `epistemic` | `mw-corpus`, `mw-nexus`, `mw-lore` | `:4420`, `:4430`, `:4450` |
| `portal` | `mw-mylove` | `:4460` |
| `studio` | `mw-studio` | `:4470` |
| `tunnel` | `cloudflared` | Zero-Trust outbound |
| `proxy` | `caddy` (`Caddyfile.template`) | `:80`, `:443` |
| `full` | All profiles combined | All above |

## 16-Repo MoonWitness Sovereign Topology

`mw-stack` orchestrates the containerized services across the 16-repository MoonWitness ecosystem, unified by `mw-rid` OIDC SSO (`https://id.<MW_DOMAIN>`) and paired with `mw-pocket` on Android:

| Layer | Repositories | Role |
| :--- | :--- | :--- |
| **Core & Identity** | `mw-echo` (`:4310`), `mw-rid` (`:4480`) | Sovereign node runtime & OIDC/JWKS identity provider (`id.a-l-l-a-h.com`) |
| **Operations** | `mw-lab` (`:4400`), `mw-mission` (`:4410`), `mw-cp` (`:4440`) | Fleet lab, mission control, and control plane |
| **SaaS & Workspace** | `mw-dock` (`:3000`), `mw-xv` (`mw-board`, `:3001`), `mw-design` (`:8080`), `mw-studio` (`:4470`) | Multi-tenant dock, board, design system, and studio |
| **Epistemic & Portal** | `mw-corpus` (`:4420`), `mw-nexus` (`:4430`), `mw-lore` (`:4450`), `mw-mylove` (`:4460`) | Knowledge corpus, graph nexus, lore, and flagship portal (`a-l-l-a-h.com`) |
| **Network & Edge** | `mw-isp` (`:8091`), `mw-stack`, `mw-pocket` | Sovereign ISP/RADIUS, fleet orchestrator, and Android companion app |

### Mobile Pairing (`mw-pocket` QR / OIDC)

1. Deploy `mw-rid` (`mwctl up id` or `ops`/`saas`/`full`) and expose `https://id.<MW_DOMAIN>` via Caddy or Cloudflare Tunnel.
2. Bootstrap the Platform Owner account once via `POST /api/bootstrap` using `RID_BOOTSTRAP_SECRET` from `.env`.
3. Open **mw-pocket** on Android and scan the pairing QR code (or enter `https://id.<MW_DOMAIN>`). `mw-pocket` discovers `/.well-known/openid-configuration`, completes PKCE OIDC sign-in against `mw-rid`, and uses RS256 access tokens verified via `http://mw-rid:4480/jwks` across `mw-echo`, `mw-lab`, `mw-cp`, `mw-dock`, and `mw-mylove`.

## `mwctl` Operator CLI

```bash
mwctl up [profile]      # Start selected profile (default: MW_PROFILE in .env)
mwctl down              # Stop fleet containers
mwctl update [profile]  # Pull latest GHCR images and recreate
mwctl status            # Inspect container status
mwctl logs [service]    # Tail service logs
mwctl backup            # Trigger mw-echo /api/storage/backup
mwctl doctor            # Run mw-echo /api/desktop/doctor & /api/disk/drives
mwctl verify            # Probe /health & OIDC contracts across all 13 services
mwctl profiles          # Print profile matrix
mwctl tunnel            # Start Cloudflare tunnel
```
