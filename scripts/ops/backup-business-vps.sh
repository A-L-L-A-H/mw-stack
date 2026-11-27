#!/usr/bin/env bash
set -euo pipefail

# 3-2-1 Automated Encrypted Backup for MoonWitness Business VPS
# 1) PostgreSQL pg_dump (PaaS, ISP, Billing)
# 2) Trigger mw-echo storage backup (/api/storage/backup -> includes optional GDrive 15GB off-site)
# 3) Encrypt tar.gz with AES-256-CBC PBKDF2 using MW_ENCRYPTION_KEY + SHA-256 checksum
# 4) Rotate local archives older than BACKUP_RETENTION_DAYS + optional rclone off-site copy
# 5) Notify ntfy.sh / Telegram on completion or failure

STACK_DIR="${MW_STACK_DIR:-/opt/mw-stack}"
ENV_FILE="$STACK_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

BACKUP_DIR="${BACKUP_DIR:-/var/backups/mw-stack}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
ECHO_URL="${MW_ECHO_URL:-http://127.0.0.1:${MW_ECHO_PORT:-4310}}"
PG_USER="${POSTGRES_USER:-moonwitness}"
PG_DB="${POSTGRES_DB:-moonwitness}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
STAGE_DIR="$(mktemp -d)"
ARCHIVE_ENC="${BACKUP_DIR}/mw-business-${STAMP}.tar.gz.enc"
SUM_FILE="${ARCHIVE_ENC}.sha256"

notify_event() {
  local title="$1" body="$2" prio="${3:-default}"
  if [[ -n "${NTFY_TOPIC_URL:-}" ]]; then
    curl -fsS -H "Title: ${title}" -H "Priority: ${prio}" -d "${body}" "${NTFY_TOPIC_URL}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${title}: ${body}" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  rm -rf "$STAGE_DIR"
}
on_error() {
  notify_event "MW Business Backup FAILED" "Backup ${STAMP} failed on $(hostname)" "urgent"
}
trap cleanup EXIT
trap on_error ERR

mkdir -p "$BACKUP_DIR"

if [[ -z "${MW_ENCRYPTION_KEY:-}" ]]; then
  echo "[mw-backup] MW_ENCRYPTION_KEY is required in .env for encrypted backups." >&2
  exit 1
fi

echo "[mw-backup] Dumping PostgreSQL (${PG_DB})..."
docker exec mw-postgres pg_dump -U "$PG_USER" -d "$PG_DB" --clean --if-exists > "$STAGE_DIR/postgres.sql"

if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$STAGE_DIR/stack.env"
fi

echo "[mw-backup] Triggering mw-echo local/off-site backup snapshot..."
curl -fsS -X POST "${ECHO_URL}/api/storage/backup" \
  -H "Authorization: Bearer ${MW_API_SECRET:-}" \
  -H "Content-Type: application/json" > "$STAGE_DIR/echo-backup-receipt.json" || echo '{"warning":"mw-echo unreachable"}' > "$STAGE_DIR/echo-backup-receipt.json"

tar -czf "$STAGE_DIR/bundle.tar.gz" -C "$STAGE_DIR" postgres.sql echo-backup-receipt.json $( [[ -f "$STAGE_DIR/stack.env" ]] && echo "stack.env" )
openssl enc -aes-256-cbc -pbkdf2 -salt -pass "env:MW_ENCRYPTION_KEY" -in "$STAGE_DIR/bundle.tar.gz" -out "$ARCHIVE_ENC"
sha256sum "$ARCHIVE_ENC" > "$SUM_FILE"

if [[ -n "${BACKUP_RCLONE_REMOTE:-}" ]] && command -v rclone >/dev/null 2>&1; then
  echo "[mw-backup] Syncing encrypted archive to rclone remote ${BACKUP_RCLONE_REMOTE}..."
  rclone copy "$ARCHIVE_ENC" "${BACKUP_RCLONE_REMOTE}"
  rclone copy "$SUM_FILE" "${BACKUP_RCLONE_REMOTE}"
fi

find "$BACKUP_DIR" -type f -name 'mw-business-*.tar.gz.enc*' -mtime +"$RETENTION_DAYS" -delete
SIZE_HUMAN="$(du -h "$ARCHIVE_ENC" | cut -f1)"
echo "[mw-backup] Completed: ${ARCHIVE_ENC} (${SIZE_HUMAN})"
notify_event "MW Business Backup OK" "Encrypted backup ${STAMP} (${SIZE_HUMAN}) ready." "default"
