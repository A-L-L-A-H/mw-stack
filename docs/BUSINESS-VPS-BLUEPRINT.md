# MoonWitness All-in-One Business VPS Blueprint (PaaS + ISP + Free-Tier Cloud)

**Profile:** `business` (`MW_PROFILE=business`)  
**Principle:** **Zero Overlap, Zero Credit Card Required, 3-2-1 Encrypted Backup & Multi-Provider Fallback**

---

## 1. Quick 1-Script Install (Fresh Linux VPS)

```bash
curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/scripts/install-business-vps.sh | \
  sudo MW_DOMAIN=example.com MW_ACME_EMAIL=ops@example.com bash
```

What this single script automates idempotently:
1. Installs Docker Engine, Compose v2, `git`, `curl`, `openssl`, `gzip` (and optional Tailscale with `--with-tailscale`).
2. Locks down UFW firewall (public: `22/tcp`, `80/tcp`, `443/tcp+udp`, RADIUS `1812/1813/3799/udp`; blocks direct access to internal DB/control ports).
3. Clones `mw-stack` (`/opt/mw-stack`) and `mw-templates` (`/opt/mw-templates`), generates random cryptographic secrets in `.env`, installs `mwctl` to `/usr/local/bin/mwctl`, and schedules daily encrypted backups at `03:00` via `/etc/cron.d/mw-stack-backup`.
4. Starts the 8 core services of `--profile business` (plus `--profile tunnel` if `CLOUDFLARE_TUNNEL_TOKEN` is configured).

---

## 2. Canonical Split: VPS Core vs Free-Tier Offload

| Service / Layer | Runs On | Memory Cap | Fallback / Backup |
| :--- | :--- | :--- | :--- |
| `caddy` (`80/443`) | **VPS** | `128m` | Optional Cloudflare Tunnel (`cloudflared`) |
| `mw-rid` (`4480`) | **VPS** | `128m` | Local SQLite volume + encrypted backup |
| `mw-isp` (`8091` + UDP `1812/1813/3799`) | **VPS** | `128m` | Local SQLite volume + MikroTik Tailscale mesh |
| `mw-cp` (`4440`) | **VPS** | `128m` | PaaS engine & Docker container host |
| `mw-echo` (`4310`) | **VPS** | `128m` | Telegram + Discord + `ntfy.sh` + `Resend` alerts; Google Drive 15GB off-site backup |
| `mw-rocksoul-gateway` (`4510`) | **VPS** | `128m` | Priority failover: **Gemini Free (50) → Groq (60) → OpenRouter `:free` (70) → NVIDIA NIM (80)** |
| `postgres` | **VPS** | `384m` | Daily `pg_dump` encrypted AES-256 + `mwctl restore-drill` |
| `mw-board` (`3001`) | **VPS** | `512m` | External `MW_TEMPLATES_DIR=/opt/mw-templates` + optional Qdrant/Turso |

---

## 3. Daily Operations (`mwctl`)

```bash
mwctl status          # Container health
mwctl backup-all      # Run immediate 3-2-1 encrypted backup + off-site sync
mwctl restore-drill   # Non-destructive decrypt + SHA-256 + gzip integrity verification
mwctl doctor          # Host & disk diagnostics
```
