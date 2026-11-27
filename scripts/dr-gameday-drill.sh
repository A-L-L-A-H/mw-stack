#!/usr/bin/env bash
set -euo pipefail

# V70: Automated DR Game Day Bootstrap & Restore Checksum Verification Drill
# Runs a self-contained local sandbox drill (no external VPS credentials required):
#   1) Bootstraps synthetic stack state (db dump, env config, storage receipt)
#   2) Archives, encrypts (AES-256-CBC PBKDF2), and computes SHA-256 checksum
#   3) Restores into a clean-room target directory and verifies checksum + byte parity
#   4) Injects a 1-byte tamper fault and verifies checksum check rejects corruption
#   5) Emits structured JSON drill report

DRY_RUN=false
SANDBOX_DIR=""
REPORT_FILE=""
KEEP_SANDBOX=false
START_EPOCH="$(date -u +%s)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

usage() {
  cat <<'EOF'
Usage: dr-gameday-drill.sh [options]

Options:
  --dry-run              Run local sandbox DR drill without external VPS credentials
  --sandbox-dir <dir>    Use a specific sandbox directory
  --report <file>        Write JSON drill report to file
  --keep-sandbox         Do not remove temporary sandbox directory on exit
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --sandbox-dir)
      SANDBOX_DIR="$2"
      shift 2
      ;;
    --report)
      REPORT_FILE="$2"
      shift 2
      ;;
    --keep-sandbox)
      KEEP_SANDBOX=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[v70-dr-drill] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

CREATED_TEMP=false
if [[ -z "$SANDBOX_DIR" ]]; then
  SANDBOX_DIR="$(mktemp -d)"
  CREATED_TEMP=true
else
  mkdir -p "$SANDBOX_DIR"
fi

cleanup() {
  if [[ "$CREATED_TEMP" == "true" && "$KEEP_SANDBOX" == "false" && -d "$SANDBOX_DIR" ]]; then
    rm -rf "$SANDBOX_DIR"
  fi
}
trap cleanup EXIT

SRC_DIR="$SANDBOX_DIR/source"
ARCHIVE_DIR="$SANDBOX_DIR/archives"
RESTORE_DIR="$SANDBOX_DIR/restore"
mkdir -p "$SRC_DIR" "$ARCHIVE_DIR" "$RESTORE_DIR"

# 1. Bootstrap synthetic DR state
cat > "$SRC_DIR/postgres.sql" <<'EOF'
-- Synthetic MoonWitness DR Game Day Dump
CREATE TABLE dr_canary (id INT PRIMARY KEY, marker TEXT NOT NULL);
INSERT INTO dr_canary VALUES (1, 'sovereign-dr-gameday-ok');
EOF
cat > "$SRC_DIR/stack.env" <<'EOF'
MW_STACK_MODE=sandbox
MW_DR_DRILL=true
EOF
cat > "$SRC_DIR/echo-receipt.json" <<'EOF'
{"status":"ok","snapshot":"dr-gameday-sandbox"}
EOF

# 2. Package, encrypt, and checksum
BUNDLE_TAR="$ARCHIVE_DIR/dr-bundle.tar.gz"
ARCHIVE_ENC="$ARCHIVE_DIR/dr-bundle.tar.gz.enc"
SUM_FILE="${ARCHIVE_ENC}.sha256"
DRILL_PASSPHRASE="${MW_DR_PASSPHRASE:-mw-dr-gameday-local-sandbox-key}"

tar -czf "$BUNDLE_TAR" -C "$SRC_DIR" postgres.sql stack.env echo-receipt.json

if command -v openssl >/dev/null 2>&1; then
  ENCRYPTION_MODE="aes-256-cbc-pbkdf2"
  openssl enc -aes-256-cbc -pbkdf2 -salt -pass "pass:${DRILL_PASSPHRASE}" -in "$BUNDLE_TAR" -out "$ARCHIVE_ENC"
else
  ENCRYPTION_MODE="fallback-copy-no-openssl"
  cp "$BUNDLE_TAR" "$ARCHIVE_ENC"
fi

(
  cd "$ARCHIVE_DIR"
  sha256sum "$(basename "$ARCHIVE_ENC")" > "$(basename "$SUM_FILE")"
)

# 3. Clean-room restore & checksum verification
(
  cd "$ARCHIVE_DIR"
  sha256sum -c "$(basename "$SUM_FILE")" >/dev/null
)

RESTORED_TAR="$RESTORE_DIR/restored.tar.gz"
if [[ "$ENCRYPTION_MODE" == "aes-256-cbc-pbkdf2" ]]; then
  openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:${DRILL_PASSPHRASE}" -in "$ARCHIVE_ENC" -out "$RESTORED_TAR"
else
  cp "$ARCHIVE_ENC" "$RESTORED_TAR"
fi

tar -xzf "$RESTORED_TAR" -C "$RESTORE_DIR"

cmp -s "$SRC_DIR/postgres.sql" "$RESTORE_DIR/postgres.sql"
cmp -s "$SRC_DIR/stack.env" "$RESTORE_DIR/stack.env"
cmp -s "$SRC_DIR/echo-receipt.json" "$RESTORE_DIR/echo-receipt.json"

# 4. Negative tamper check: flip 1 byte and confirm sha256sum -c fails
TAMPER_ENC="$ARCHIVE_DIR/dr-bundle-tampered.tar.gz.enc"
TAMPER_SUM="$ARCHIVE_DIR/dr-bundle-tampered.tar.gz.enc.sha256"
cp "$ARCHIVE_ENC" "$TAMPER_ENC"
printf '\xff' >> "$TAMPER_ENC"
sed "s/$(basename "$ARCHIVE_ENC")/$(basename "$TAMPER_ENC")/" "$SUM_FILE" > "$TAMPER_SUM"

TAMPER_REJECTED=false
if (cd "$ARCHIVE_DIR" && sha256sum -c "$(basename "$TAMPER_SUM")" >/dev/null 2>&1); then
  echo "[v70-dr-drill] ERROR: Tampered archive unexpectedly passed checksum verification!" >&2
  exit 1
else
  TAMPER_REJECTED=true
fi

END_EPOCH="$(date -u +%s)"
RTO_SECONDS=$((END_EPOCH - START_EPOCH))

REPORT_JSON="$(cat <<EOF
{
  "drill": "v70-dr-gameday",
  "status": "PASS",
  "dryRun": ${DRY_RUN},
  "timestamp": "${STAMP}",
  "encryptionMode": "${ENCRYPTION_MODE}",
  "rtoSeconds": ${RTO_SECONDS},
  "checks": {
    "bootstrap": true,
    "checksumVerified": true,
    "restoreParity": true,
    "tamperRejected": ${TAMPER_REJECTED}
  }
}
EOF
)"

if [[ -n "$REPORT_FILE" ]]; then
  mkdir -p "$(dirname "$REPORT_FILE")"
  printf '%s\n' "$REPORT_JSON" > "$REPORT_FILE"
fi

printf '%s\n' "$REPORT_JSON"
