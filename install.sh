#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${MW_STACK_REPO:-https://github.com/A-L-L-A-H/mw-stack.git}"
INSTALL_DIR="${MW_STACK_DIR:-/opt/mw-stack}"
PROFILE="${MW_PROFILE:-}"
SKIP_START="${MW_SKIP_START:-0}"

usage() {
  cat <<'EOF'
MoonWitness Sovereign Fleet Installer (mw-stack)

Usage:
  curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/A-L-L-A-H/mw-stack/main/install.sh | MW_PROFILE=ops bash
  ./install.sh --profile lite|id|ops|saas|isp|epistemic|portal|studio|rocksoul|full [--dir /opt/mw-stack] [--no-start]

Options:
  --profile <name>   Fleet profile (lite, id, ops, saas, isp, epistemic, portal, studio, rocksoul, tunnel, proxy, full)
  --dir <path>       Installation directory (default: /opt/mw-stack)
  --no-start         Install and configure without starting containers
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --no-start)
      SKIP_START=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[mw-stack] Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "[mw-stack] Root privileges or sudo required." >&2
    exit 1
  fi
fi

validate_profile() {
  case "$1" in
    lite|id|ops|saas|isp|epistemic|portal|studio|rocksoul|tunnel|proxy|full) return 0 ;;
    *)
      echo "[mw-stack] Invalid profile '$1'. Allowed: lite, id, ops, saas, isp, epistemic, portal, studio, rocksoul, tunnel, proxy, full" >&2
      exit 1
      ;;
  esac
}

if [[ -z "$PROFILE" ]]; then
  if [[ -t 0 ]]; then
    echo "Select MoonWitness deployment profile:"
    echo "  1) lite       - mw-echo core node (:4310)"
    echo "  2) id         - mw-rid OIDC identity provider (:4480)"
    echo "  3) ops        - mw-echo + mw-rid + mw-lab + mw-mission + mw-cp"
    echo "  4) saas       - postgres + mw-rid + mw-dock + mw-design + mw-board"
    echo "  5) isp        - mw-isp (:8091 + RADIUS UDP 1812/1813)"
    echo "  6) epistemic  - mw-corpus + mw-nexus + mw-lore"
    echo "  7) rocksoul   - mw-rocksoul-gateway + core + mcp + sandbox (:4510-:4540)"
    echo "  8) full       - all services + caddy proxy + cloudflared tunnel"
    read -r -p "Profile [lite]: " selected_profile
    case "${selected_profile:-lite}" in
      1|lite) PROFILE="lite" ;;
      2|id) PROFILE="id" ;;
      3|ops) PROFILE="ops" ;;
      4|saas) PROFILE="saas" ;;
      5|isp) PROFILE="isp" ;;
      6|epistemic) PROFILE="epistemic" ;;
      7|rocksoul) PROFILE="rocksoul" ;;
      8|full) PROFILE="full" ;;
      *) PROFILE="$selected_profile" ;;
    esac
  else
    PROFILE="lite"
  fi
fi
validate_profile "$PROFILE"

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[mw-stack] Installing Docker Engine..."
    curl -fsSL https://get.docker.com | $SUDO sh
    if command -v systemctl >/dev/null 2>&1; then
      $SUDO systemctl enable --now docker
    fi
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "[mw-stack] Docker Compose v2 plugin not detected. Installing docker-compose-plugin..."
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -y
      $SUDO apt-get install -y docker-compose-plugin
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y docker-compose-plugin
    elif command -v yum >/dev/null 2>&1; then
      $SUDO yum install -y docker-compose-plugin
    else
      echo "[mw-stack] Unable to install Docker Compose v2 automatically. Install docker-compose-plugin and retry." >&2
      exit 1
    fi
  fi
}

ensure_dependencies() {
  local missing=()
  for bin in git curl openssl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing+=("$bin")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[mw-stack] Installing missing prerequisites: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -y
      $SUDO apt-get install -y "${missing[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y "${missing[@]}"
    elif command -v yum >/dev/null 2>&1; then
      $SUDO yum install -y "${missing[@]}"
    else
      echo "[mw-stack] Missing required tools: ${missing[*]}" >&2
      exit 1
    fi
  fi
}

sync_repo() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "[mw-stack] Updating existing installation in $INSTALL_DIR..."
    $SUDO git -C "$INSTALL_DIR" fetch --all --prune
    $SUDO git -C "$INSTALL_DIR" pull --ff-only origin main
  else
    echo "[mw-stack] Cloning $REPO_URL into $INSTALL_DIR..."
    $SUDO mkdir -p "$(dirname "$INSTALL_DIR")"
    $SUDO git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
}

generate_env() {
  local env_file="$INSTALL_DIR/.env"
  if [[ -f "$env_file" ]]; then
    echo "[mw-stack] Existing .env found at $env_file (preserving secrets)."
    return 0
  fi

  echo "[mw-stack] Generating cryptographic secrets in $env_file..."
  local api_secret jwt_secret enc_key pg_pass
  api_secret="$(openssl rand -hex 24)"
  jwt_secret="$(openssl rand -hex 24)"
  enc_key="$(openssl rand -hex 24)"
  pg_pass="$(openssl rand -hex 24)"

  $SUDO cp "$INSTALL_DIR/.env.example" "$env_file"
  $SUDO sed -i \
    -e "s|^MW_PROFILE=.*|MW_PROFILE=${PROFILE}|" \
    -e "s|^MW_API_SECRET=.*|MW_API_SECRET=${api_secret}|" \
    -e "s|^MW_JWT_SECRET=.*|MW_JWT_SECRET=${jwt_secret}|" \
    -e "s|^MW_ENCRYPTION_KEY=.*|MW_ENCRYPTION_KEY=${enc_key}|" \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pg_pass}|" \
    "$env_file"
  $SUDO chmod 600 "$env_file"
}

install_cli() {
  echo "[mw-stack] Installing mwctl to /usr/local/bin/mwctl..."
  $SUDO install -m 0755 "$INSTALL_DIR/mwctl" /usr/local/bin/mwctl
}

start_stack() {
  echo "[mw-stack] Pulling GHCR images for profile '${PROFILE}'..."
  $SUDO docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" --profile "$PROFILE" pull
  echo "[mw-stack] Starting MoonWitness fleet (profile: ${PROFILE})..."
  $SUDO docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" --profile "$PROFILE" up -d --remove-orphans
}

ensure_dependencies
ensure_docker
sync_repo
generate_env
install_cli

if [[ "$SKIP_START" -eq 0 ]]; then
  start_stack
fi

echo "[mw-stack] Deployment complete. Run 'mwctl status' to inspect the fleet."
