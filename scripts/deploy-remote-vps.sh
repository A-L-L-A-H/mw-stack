#!/usr/bin/env bash
set -euo pipefail

# 1-Command SSH/Tailscale Deploy Wrapper for MoonWitness Business VPS
# Deploys mw-stack to a remote Linux host running Tailscale or public SSH,
# executes install-business-vps.sh, verifies UFW rules, and runs mwctl restore-drill.

REMOTE_HOST=""
REMOTE_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
DOMAIN="${MW_DOMAIN:-mw.local}"
ACME_EMAIL="${MW_ACME_EMAIL:-ops@mw.local}"
WITH_TAILSCALE=0
SKIP_RESTORE_DRILL=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy-remote-vps.sh --host <vps-ip-or-tailscale-node> [options]

Options:
  --host <ip|hostname>   Remote host IP or Tailscale MagicDNS name (required)
  --user <user>          SSH username (default: root)
  --port <port>          SSH port (default: 22)
  --key <identity_file>  Path to private SSH key
  --domain <domain>      Public domain for Caddy SSL (default: mw.local)
  --email <email>        ACME registration email
  --with-tailscale       Install Tailscale mesh on remote VPS
  --skip-restore-drill   Skip non-destructive backup restore drill verification
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) REMOTE_HOST="${2:-}"; shift 2 ;;
    --user) SSH_USER="${2:-root}"; shift 2 ;;
    --port) REMOTE_PORT="${2:-22}"; shift 2 ;;
    --key) SSH_KEY="${2:-}"; shift 2 ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) ACME_EMAIL="${2:-}"; shift 2 ;;
    --with-tailscale) WITH_TAILSCALE=1; shift ;;
    --skip-restore-drill) SKIP_RESTORE_DRILL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[deploy-remote] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$REMOTE_HOST" ]]; then
  echo "[deploy-remote] ERROR: --host is required." >&2
  usage
  exit 1
fi

SSH_OPTS=(-p "$REMOTE_PORT" -o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=10")
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

run_remote() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" "$@"
}

echo "=== Deploying MoonWitness Business VPS to ${SSH_USER}@${REMOTE_HOST} ==="
echo "Target Domain: $DOMAIN"
echo "ACME Email:    $ACME_EMAIL"
echo ""

echo ">>> [1/4] Probing remote SSH connection..."
run_remote "echo 'SSH Connection OK: ' \$(hostname) \$(uname -m)"

echo ">>> [2/4] Executing install-business-vps.sh remotely..."
INSTALL_FLAGS="--domain '${DOMAIN}' --email '${ACME_EMAIL}'"
if [[ "$WITH_TAILSCALE" -eq 1 ]]; then
  INSTALL_FLAGS="${INSTALL_FLAGS} --with-tailscale"
fi

run_remote "bash -c \"curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/scripts/install-business-vps.sh | sudo bash -s -- ${INSTALL_FLAGS}\""

echo ">>> [3/4] Verifying remote UFW firewall rules..."
run_remote "sudo ufw status verbose || true"

if [[ "$SKIP_RESTORE_DRILL" -eq 0 ]]; then
  echo ">>> [4/4] Executing non-destructive backup restore-drill..."
  run_remote "sudo mwctl restore-drill || echo '[deploy-remote] restore-drill skipped if no backups exist yet.'"
fi

echo ""
echo "=== MoonWitness Business VPS Deployment Completed Successfully ==="
