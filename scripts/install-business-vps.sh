#!/usr/bin/env bash
set -euo pipefail

# MoonWitness All-in-One Business VPS Installer (PaaS + ISP + Billing + Free-Tier Offload)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/scripts/install-business-vps.sh | sudo MW_DOMAIN=example.com bash
#   ./scripts/install-business-vps.sh --domain app.example.com --email ops@example.com [--with-tailscale] [--skip-ufw] [--no-start]

REPO_URL="${MW_STACK_REPO:-https://github.com/A-L-L-A-H/mw-stack.git}"
TEMPLATES_REPO_URL="${MW_TEMPLATES_REPO:-https://github.com/A-L-L-A-H/mw-templates.git}"
INSTALL_DIR="${MW_STACK_DIR:-/opt/mw-stack}"
TEMPLATES_DIR="${MW_TEMPLATES_DIR:-/opt/mw-templates}"
DOMAIN="${MW_DOMAIN:-mw.local}"
ACME_EMAIL="${MW_ACME_EMAIL:-ops@mw.local}"
WITH_TAILSCALE="${MW_WITH_TAILSCALE:-0}"
SKIP_UFW="${MW_SKIP_UFW:-0}"
SKIP_START="${MW_SKIP_START:-0}"

usage() {
  cat <<'EOF'
MoonWitness All-in-One Business VPS Installer

Usage:
  ./install-business-vps.sh [options]

Options:
  --domain <domain>    Public domain for Caddy wildcard SSL (default: mw.local)
  --email <email>      ACME email for Let's Encrypt TLS (default: ops@mw.local)
  --dir <path>         Install directory (default: /opt/mw-stack)
  --with-tailscale     Install Tailscale client for private admin/MikroTik VPN mesh
  --skip-ufw           Skip UFW firewall configuration
  --no-start           Configure .env, cron, and binaries without starting Docker containers
  -h, --help           Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) ACME_EMAIL="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --with-tailscale) WITH_TAILSCALE=1; shift ;;
    --skip-ufw) SKIP_UFW=1; shift ;;
    --no-start) SKIP_START=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[mw-business] Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "[mw-business] Root privileges or sudo required." >&2
    exit 1
  fi
fi

ensure_base_packages() {
  local missing=()
  for cmd in git curl openssl gzip; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[mw-business] Installing base packages: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -y && $SUDO apt-get install -y "${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y "${missing[@]}"
    elif command -v yum >/dev/null 2>&1; then
      $SUDO yum install -y "${missing[@]}"
    else
      echo "[mw-business] Missing required packages: ${missing[*]}" >&2
      exit 1
    fi
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[mw-business] Installing Docker Engine..."
    curl -fsSL https://get.docker.com | $SUDO sh
    command -v systemctl >/dev/null 2>&1 && $SUDO systemctl enable --now docker
  fi
  if ! docker compose version >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -y && $SUDO apt-get install -y docker-compose-plugin
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y docker-compose-plugin
    else
      echo "[mw-business] Docker Compose v2 required." >&2
      exit 1
    fi
  fi
}

ensure_tailscale() {
  if [[ "$WITH_TAILSCALE" -eq 1 ]] && ! command -v tailscale >/dev/null 2>&1; then
    echo "[mw-business] Installing Tailscale VPN mesh client..."
    curl -fsSL https://tailscale.com/install.sh | $SUDO sh || echo "[mw-business] Warning: Tailscale install failed, continuing." >&2
  fi
}

configure_ufw() {
  if [[ "$SKIP_UFW" -eq 1 ]] || ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  echo "[mw-business] Configuring UFW firewall (public: 22, 80, 443, RADIUS 1812/1813/3799; internal ports blocked)..."
  $SUDO ufw allow 22/tcp >/dev/null
  $SUDO ufw allow 80/tcp >/dev/null
  $SUDO ufw allow 443/tcp >/dev/null
  $SUDO ufw allow 443/udp >/dev/null
  $SUDO ufw allow 1812/udp >/dev/null
  $SUDO ufw allow 1813/udp >/dev/null
  $SUDO ufw allow 3799/udp >/dev/null
  if ip link show tailscale0 >/dev/null 2>&1; then
    $SUDO ufw allow in on tailscale0 >/dev/null
  fi
  $SUDO ufw --force enable >/dev/null || true
}

sync_repos() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    $SUDO git -C "$INSTALL_DIR" fetch --all --prune && $SUDO git -C "$INSTALL_DIR" pull --ff-only origin main
  else
    $SUDO mkdir -p "$(dirname "$INSTALL_DIR")"
    $SUDO git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
  if [[ -d "$TEMPLATES_DIR/.git" ]]; then
    $SUDO git -C "$TEMPLATES_DIR" pull --ff-only origin main || true
  else
    $SUDO mkdir -p "$(dirname "$TEMPLATES_DIR")"
    $SUDO git clone --depth 1 "$TEMPLATES_REPO_URL" "$TEMPLATES_DIR" || echo "[mw-business] Warning: mw-templates clone skipped." >&2
  fi
}

set_env_if_present() {
  local file="$1" key="$2" val="${3:-}"
  if [[ -n "$val" ]]; then
    if grep -q "^${key}=" "$file"; then
      $SUDO sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
      echo "${key}=${val}" | $SUDO tee -a "$file" >/dev/null
    fi
  fi
}

configure_env() {
  local env_file="$INSTALL_DIR/.env"
  if [[ ! -f "$env_file" ]]; then
    echo "[mw-business] Generating business .env with cryptographic secrets..."
    $SUDO cp "$INSTALL_DIR/.env.example" "$env_file"
    set_env_if_present "$env_file" "MW_PROFILE" "business"
    set_env_if_present "$env_file" "MW_DOMAIN" "$DOMAIN"
    set_env_if_present "$env_file" "MW_ACME_EMAIL" "$ACME_EMAIL"
    set_env_if_present "$env_file" "MW_API_SECRET" "$(openssl rand -hex 24)"
    set_env_if_present "$env_file" "MW_JWT_SECRET" "$(openssl rand -hex 24)"
    set_env_if_present "$env_file" "MW_ENCRYPTION_KEY" "$(openssl rand -hex 24)"
    set_env_if_present "$env_file" "POSTGRES_PASSWORD" "$(openssl rand -hex 24)"
    set_env_if_present "$env_file" "MW_TEMPLATES_DIR" "$TEMPLATES_DIR"
  else
    echo "[mw-business] Preserving existing $env_file secrets."
  fi

  for opt_var in GEMINI_API_KEY GROQ_API_KEY OPENROUTER_API_KEY NVIDIA_API_KEY \
    NTFY_TOPIC_URL TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID RESEND_API_KEY \
    OTEL_EXPORTER_OTLP_ENDPOINT QDRANT_URL TURSO_DATABASE_URL CLOUDFLARE_TUNNEL_TOKEN; do
    set_env_if_present "$env_file" "$opt_var" "${!opt_var:-}"
  done
  $SUDO chmod 600 "$env_file"
}

install_cli_and_backup_cron() {
  $SUDO install -m 0755 "$INSTALL_DIR/mwctl" /usr/local/bin/mwctl
  $SUDO chmod +x "$INSTALL_DIR/scripts/backup-business-vps.sh" "$INSTALL_DIR/scripts/restore-business-vps.sh"
  $SUDO mkdir -p /var/backups/mw-stack
  if [[ -d /etc/cron.d ]]; then
    echo "0 3 * * * root MW_STACK_DIR=${INSTALL_DIR} ${INSTALL_DIR}/scripts/backup-business-vps.sh >> /var/log/mw-stack-backup.log 2>&1" | $SUDO tee /etc/cron.d/mw-stack-backup >/dev/null
    $SUDO chmod 644 /etc/cron.d/mw-stack-backup
  fi
}

start_business_stack() {
  local env_file="$INSTALL_DIR/.env"
  local compose_file="$INSTALL_DIR/docker-compose.yml"
  local profile_args=(--profile business)
  if grep -q '^CLOUDFLARE_TUNNEL_TOKEN=.\+' "$env_file" 2>/dev/null; then
    profile_args+=(--profile tunnel)
  fi
  echo "[mw-business] Pulling images and starting business stack..."
  $SUDO docker compose -f "$compose_file" --env-file "$env_file" "${profile_args[@]}" pull
  $SUDO docker compose -f "$compose_file" --env-file "$env_file" "${profile_args[@]}" up -d --remove-orphans
  $SUDO docker compose -f "$compose_file" --env-file "$env_file" --profile business ps
}

ensure_base_packages
ensure_docker
ensure_tailscale
configure_ufw
sync_repos
configure_env
install_cli_and_backup_cron

if [[ "$SKIP_START" -eq 0 ]]; then
  start_business_stack
fi

echo "[mw-business] All-in-One Business VPS ready! Use 'mwctl status', 'mwctl backup-all', 'mwctl restore-drill'."
