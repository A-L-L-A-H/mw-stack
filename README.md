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
| `ops` | `mw-echo`, `mw-lab`, `mw-mission`, `mw-cp` | `:4310`, `:4400`, `:4410`, `:4440` |
| `saas` | `postgres`, `mw-dock`, `mw-design`, `mw-board` | `:3000`, `:8080`, `:3001` |
| `isp` | `mw-isp` | `:8091`, `1812/udp`, `1813/udp` |
| `epistemic` | `mw-corpus`, `mw-nexus`, `mw-lore` | `:4420`, `:4430`, `:4450` |
| `tunnel` | `cloudflared` | Zero-Trust outbound |
| `proxy` | `caddy` (`Caddyfile.template`) | `:80`, `:443` |
| `full` | All profiles combined | All above |

## `mwctl` Operator CLI

```bash
mwctl up [profile]      # Start selected profile (default: MW_PROFILE in .env)
mwctl down              # Stop fleet containers
mwctl update [profile]  # Pull latest GHCR images and recreate
mwctl status            # Inspect container status
mwctl logs [service]    # Tail service logs
mwctl backup            # Trigger mw-echo /api/storage/backup
mwctl doctor            # Run mw-echo /api/desktop/doctor & /api/disk/drives
mwctl profiles          # Print profile matrix
mwctl tunnel            # Start Cloudflare tunnel
```
