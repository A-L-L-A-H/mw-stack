#!/usr/bin/env bash
set -euo pipefail

# 1-Command SSH/Tailscale Deploy Wrapper for MoonWitness Business VPS
# Uploads local mw-stack, mw-templates, and mw-ww-cli bundles over tar|ssh
# (zero unauthenticated remote raw-file fetches on private repos),
# executes install-business-vps.sh, verifies UFW rules, and runs mwctl restore-drill.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_STACK_DIR="${MW_STACK_LOCAL_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
LOCAL_TEMPLATES_DIR="${MW_TEMPLATES_LOCAL_DIR:-$(cd "${LOCAL_STACK_DIR}/.." && pwd)/mw-templates}"
LOCAL_WW_CLI="${MW_WW_CLI_BIN:-$(cd "${LOCAL_STACK_DIR}/.." && pwd)/mw-ww/bin/mw-ww-cli-linux-amd64}"

REMOTE_HOST=""
REMOTE_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
DOMAIN="${MW_DOMAIN:-mw.local}"
PORTAL_DOMAIN="${MW_PORTAL_DOMAIN:-}"
ACME_EMAIL="${MW_ACME_EMAIL:-ops@mw.local}"
REMOTE_STACK_DIR="${MW_STACK_DIR:-/opt/mw-stack}"
REMOTE_TEMPLATES_DIR="${MW_TEMPLATES_DIR:-/opt/mw-templates}"
WITH_TAILSCALE=0
SKIP_UFW=0
NO_START=0
SKIP_RESTORE_DRILL=0
PHASE1=0
BUSINESS=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/ops/deploy-remote-vps.sh --host <vps-ip-or-tailscale-node> [options]

Options:
  --host <ip|hostname>     Remote host IP or Tailscale MagicDNS name (required)
  --user <user>            SSH username (default: root)
  --port <port>            SSH port (default: 22)
  --key <identity_file>    Path to private SSH key
  --domain <domain>        Public domain for Caddy SSL (default: mw.local)
  --portal-domain <domain> Public portal domain for mw-mylove (optional)
  --email <email>          ACME registration email
  --dir <path>             Remote mw-stack directory (default: /opt/mw-stack)
  --with-tailscale         Install Tailscale mesh on remote VPS
  --skip-ufw               Skip UFW firewall configuration
  --no-start               Stage bundle & config without starting containers
  --skip-restore-drill     Skip non-destructive backup restore drill verification
  --phase1                 Phase 1 cutover/staging for mw-rid (:4480) + mw-echo (:4310) behind Caddy TLS
  --business               Commercial revenue bundle staging/cutover (mw-mylove, mw-cp + docker-socket-proxy, mw-isp, mw-dock) behind Caddy TLS
  -h, --help               Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) REMOTE_HOST="${2:-}"; shift 2 ;;
    --user) SSH_USER="${2:-root}"; shift 2 ;;
    --port) REMOTE_PORT="${2:-22}"; shift 2 ;;
    --key) SSH_KEY="${2:-}"; shift 2 ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --portal-domain) PORTAL_DOMAIN="${2:-}"; shift 2 ;;
    --email) ACME_EMAIL="${2:-}"; shift 2 ;;
    --dir) REMOTE_STACK_DIR="${2:-/opt/mw-stack}"; shift 2 ;;
    --with-tailscale) WITH_TAILSCALE=1; shift ;;
    --skip-ufw) SKIP_UFW=1; shift ;;
    --no-start) NO_START=1; shift ;;
    --skip-restore-drill) SKIP_RESTORE_DRILL=1; shift ;;
    --phase1) PHASE1=1; shift ;;
    --business) BUSINESS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[deploy-remote] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$REMOTE_HOST" ]]; then
  echo "[deploy-remote] ERROR: --host is required." >&2
  usage
  exit 1
fi

if [[ ! -f "${LOCAL_STACK_DIR}/docker-compose.yml" ]]; then
  echo "[deploy-remote] ERROR: Local mw-stack bundle not found at ${LOCAL_STACK_DIR}." >&2
  exit 1
fi

SSH_OPTS=(-p "$REMOTE_PORT" -o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=10")
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

REMOTE_SUDO=""
if [[ "$SSH_USER" != "root" ]]; then
  REMOTE_SUDO="sudo "
fi

run_remote() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${REMOTE_HOST}" "$@"
}

echo "=== Deploying MoonWitness Business VPS to ${SSH_USER}@${REMOTE_HOST}:${REMOTE_PORT} ==="
echo "Local Bundle:  $LOCAL_STACK_DIR -> $REMOTE_STACK_DIR"
echo "Target Domain: $DOMAIN"
if [[ -n "$PORTAL_DOMAIN" ]]; then
  echo "Portal Domain: $PORTAL_DOMAIN"
fi
echo "ACME Email:    $ACME_EMAIL"
echo ""

echo ">>> [1/5] Probing remote SSH connection..."
run_remote "echo 'SSH Connection OK: ' \$(hostname) \$(uname -m)"

echo ">>> [2/5] Uploading local mw-stack & mw-templates bundle via tar|ssh..."
tar -C "$LOCAL_STACK_DIR" \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='.env' \
  -czf - . | run_remote "${REMOTE_SUDO}mkdir -p '${REMOTE_STACK_DIR}' && ${REMOTE_SUDO}tar -xzf - -C '${REMOTE_STACK_DIR}'"

if [[ -d "$LOCAL_TEMPLATES_DIR" ]]; then
  echo "    Uploading mw-templates -> ${REMOTE_TEMPLATES_DIR}..."
  tar -C "$LOCAL_TEMPLATES_DIR" \
    --exclude='.git' \
    --exclude='node_modules' \
    -czf - . | run_remote "${REMOTE_SUDO}mkdir -p '${REMOTE_TEMPLATES_DIR}' && ${REMOTE_SUDO}tar -xzf - -C '${REMOTE_TEMPLATES_DIR}'"
else
  echo "    [warn] Local mw-templates not found at ${LOCAL_TEMPLATES_DIR}; skipping templates bundle upload."
fi

if [[ -f "$LOCAL_WW_CLI" ]]; then
  echo "    Uploading mw-ww-cli-linux-amd64 -> ${REMOTE_STACK_DIR}/bin/..."
  tar -C "$(dirname "$LOCAL_WW_CLI")" -czf - "$(basename "$LOCAL_WW_CLI")" | \
    run_remote "${REMOTE_SUDO}mkdir -p '${REMOTE_STACK_DIR}/bin' && ${REMOTE_SUDO}tar -xzf - -C '${REMOTE_STACK_DIR}/bin' && ${REMOTE_SUDO}chmod 0755 '${REMOTE_STACK_DIR}/bin/$(basename "$LOCAL_WW_CLI")'"
fi

if [[ "$PHASE1" -eq 1 ]]; then
  echo ">>> [3/5] Validating Phase 1 (mw-rid :4480 + mw-echo :4310 behind Caddy TLS) compose config..."
  run_remote "cd '${REMOTE_STACK_DIR}' && docker compose --profile id --profile lite config -q && echo '[phase1] compose config valid'"
  if [[ "$NO_START" -eq 0 ]]; then
    echo "    Starting Phase 1 services (mw-rid + mw-echo)..."
    run_remote "cd '${REMOTE_STACK_DIR}' && ${REMOTE_SUDO}docker compose --profile id --profile lite up -d mw-rid mw-echo"
    echo "    Probing Phase 1 HTTPS health endpoints behind Caddy TLS..."
    run_remote "curl -fsS -o /dev/null -w 'id.${DOMAIN}/healthz=%{http_code}\n' 'https://id.${DOMAIN}/healthz' && curl -fsS -o /dev/null -w 'echo.${DOMAIN}/healthz=%{http_code}\n' 'https://echo.${DOMAIN}/healthz'"
  else
    echo "    [--no-start] Phase 1 bundle staged & compose validated without starting containers."
  fi
elif [[ "$BUSINESS" -eq 1 ]]; then
  echo ">>> [3/5] Validating Commercial Revenue bundle (mw-mylove, mw-cp + docker-socket-proxy, mw-isp, mw-dock behind Caddy TLS)..."
  run_remote "cd '${REMOTE_STACK_DIR}' && docker compose -f docker-compose.yml -f docker-compose.proxy.yml --profile business config -q && echo '[business] compose+proxy config valid'"
  if [[ "$NO_START" -eq 0 ]]; then
    echo "    Starting Commercial Revenue services (docker-socket-proxy, mw-cp, mw-mylove, mw-isp, mw-dock)..."
    run_remote "cd '${REMOTE_STACK_DIR}' && ${REMOTE_SUDO}docker compose -f docker-compose.yml -f docker-compose.proxy.yml --profile business up -d docker-socket-proxy mw-cp mw-mylove mw-isp mw-dock"
  else
    echo "    [--no-start] Commercial Revenue bundle staged & compose+proxy validated without starting containers."
  fi
else
  echo ">>> [3/5] Executing staged install-business-vps.sh remotely..."
  INSTALL_ARGS=(--skip-sync --dir "$REMOTE_STACK_DIR" --domain "$DOMAIN" --email "$ACME_EMAIL")
  if [[ -n "$PORTAL_DOMAIN" ]]; then
    INSTALL_ARGS+=(--portal-domain "$PORTAL_DOMAIN")
  fi
  if [[ "$WITH_TAILSCALE" -eq 1 ]]; then
    INSTALL_ARGS+=(--with-tailscale)
  fi
  if [[ "$SKIP_UFW" -eq 1 ]]; then
    INSTALL_ARGS+=(--skip-ufw)
  fi
  if [[ "$NO_START" -eq 1 ]]; then
    INSTALL_ARGS+=(--no-start)
  fi

  QUOTED_INSTALL_ARGS=""
  for arg in "${INSTALL_ARGS[@]}"; do
    printf -v escaped '%q' "$arg"
    QUOTED_INSTALL_ARGS="${QUOTED_INSTALL_ARGS} ${escaped}"
  done

  run_remote "${REMOTE_SUDO}env MW_SKIP_REPO_SYNC=1 MW_STACK_DIR='${REMOTE_STACK_DIR}' MW_TEMPLATES_DIR='${REMOTE_TEMPLATES_DIR}' bash '${REMOTE_STACK_DIR}/scripts/ops/install-business-vps.sh'${QUOTED_INSTALL_ARGS}"
fi

echo ">>> [4/5] Verifying remote UFW firewall rules..."
run_remote "${REMOTE_SUDO}ufw status verbose || true"

if [[ "$SKIP_RESTORE_DRILL" -eq 0 ]]; then
  echo ">>> [5/5] Executing non-destructive backup restore-drill..."
  run_remote "${REMOTE_SUDO}mwctl restore-drill || echo '[deploy-remote] restore-drill skipped if no backups exist yet.'"
fi

echo ""
echo "=== MoonWitness Business VPS Deployment Completed Successfully ==="
