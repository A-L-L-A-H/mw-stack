#!/usr/bin/env bash
set -euo pipefail

# Verify or Restore Encrypted MoonWitness Business VPS Backup
# Usage:
#   ./scripts/restore-business-vps.sh --verify-only [archive.tar.gz.enc]
#   ./scripts/restore-business-vps.sh --apply <archive.tar.gz.enc>

STACK_DIR="${MW_STACK_DIR:-/opt/mw-stack}"
ENV_FILE="$STACK_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

BACKUP_DIR="${BACKUP_DIR:-/var/backups/mw-stack}"
PG_USER="${POSTGRES_USER:-moonwitness}"
PG_DB="${POSTGRES_DB:-moonwitness}"
MODE="verify"
ARCHIVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only) MODE="verify"; shift ;;
    --apply) MODE="apply"; ARCHIVE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--verify-only [file] | --apply <file>]"
      exit 0
      ;;
    *) ARCHIVE="$1"; shift ;;
  esac
done

if [[ -z "$ARCHIVE" ]]; then
  ARCHIVE="$(ls -1t "${BACKUP_DIR}"/mw-business-*.tar.gz.enc 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "[mw-restore] No encrypted backup archive found in ${BACKUP_DIR}." >&2
  exit 1
fi
if [[ -z "${MW_ENCRYPTION_KEY:-}" ]]; then
  echo "[mw-restore] MW_ENCRYPTION_KEY is required to decrypt backups." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -f "${ARCHIVE}.sha256" ]]; then
  sha256sum -c "${ARCHIVE}.sha256"
fi

openssl enc -d -aes-256-cbc -pbkdf2 -pass "env:MW_ENCRYPTION_KEY" -in "$ARCHIVE" -out "$TMP_DIR/bundle.tar.gz"
gzip -t "$TMP_DIR/bundle.tar.gz"
tar -tzf "$TMP_DIR/bundle.tar.gz"

if [[ "$MODE" == "verify" ]]; then
  echo "[mw-restore] DRILL PASS: ${ARCHIVE} decrypted and verified cleanly (non-destructive)."
  exit 0
fi

tar -xzf "$TMP_DIR/bundle.tar.gz" -C "$TMP_DIR"
if [[ ! -f "$TMP_DIR/postgres.sql" ]]; then
  echo "[mw-restore] postgres.sql missing in archive." >&2
  exit 1
fi

echo "[mw-restore] Restoring PostgreSQL (${PG_DB}) from ${ARCHIVE}..."
docker exec -i mw-postgres psql -U "$PG_USER" -d "$PG_DB" < "$TMP_DIR/postgres.sql"
echo "[mw-restore] Restore completed cleanly."
