#!/usr/bin/env bash
set -euo pipefail

# V36: Zero-Card Scheduled Container & Git Repo Vulnerability Audit
# Uses 100% free, local/OSS Trivy + Gitleaks (native binary or Docker fallback).
# Zero paid SaaS subscriptions, zero API keys required.

STACK_DIR="${MW_STACK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_DIR="${STACK_DIR}"
PROFILE="${MW_PROFILE:-business}"
SEVERITY="${TRIVY_SEVERITY:-CRITICAL,HIGH}"
OUTPUT_DIR="${AUDIT_OUTPUT_DIR:-${STACK_DIR}/audit-reports}"
DRY_RUN="false"
FAIL_ON_CRITICAL="false"
INSTALL_CRON="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/audit-vulns-zero-card.sh [options]

Options:
  --repo-dir <dir>       Git repository directory to scan (default: stack root)
  --profile <profile>    Docker Compose profile for image scanning (default: business)
  --severity <list>      Trivy severity filter (default: CRITICAL,HIGH)
  --output-dir <dir>     Directory for JSON reports (default: ./audit-reports)
  --fail-on-critical     Exit non-zero if CRITICAL vulnerabilities or secrets are found
  --dry-run              Print planned Trivy + Gitleaks commands without executing scans
  --install-cron         Install weekly Sunday 03:00 UTC cron job (/etc/cron.d/mw-audit-vulns)
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-business}"; shift 2 ;;
    --severity) SEVERITY="${2:-CRITICAL,HIGH}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --fail-on-critical) FAIL_ON_CRITICAL="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --install-cron) INSTALL_CRON="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[audit-vulns] ERROR: Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$INSTALL_CRON" == "true" ]]; then
  CRON_FILE="/etc/cron.d/mw-audit-vulns"
  CRON_LINE="0 3 * * 0 root ${STACK_DIR}/scripts/audit-vulns-zero-card.sh --repo-dir ${REPO_DIR} --profile ${PROFILE} --output-dir /var/log/mw-audit >> /var/log/mw-audit.log 2>&1"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[audit-vulns] [dry-run] Would write ${CRON_FILE}: ${CRON_LINE}"
    exit 0
  fi
  printf '%s\n' "$CRON_LINE" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  echo "[audit-vulns] Installed weekly cron job at ${CRON_FILE}"
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
GITLEAKS_REPORT="${OUTPUT_DIR}/gitleaks-${STAMP}.json"
TRIVY_FS_REPORT="${OUTPUT_DIR}/trivy-fs-${STAMP}.json"
TRIVY_EXIT_CODE=0
if [[ "$FAIL_ON_CRITICAL" == "true" ]]; then
  TRIVY_EXIT_CODE=1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[audit-vulns] [dry-run] Repo: ${REPO_DIR} | Profile: ${PROFILE} | Severity: ${SEVERITY}"
  echo "[audit-vulns] [dry-run] Gitleaks report: ${GITLEAKS_REPORT}"
  echo "[audit-vulns] [dry-run] Trivy FS report: ${TRIVY_FS_REPORT}"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

echo "[audit-vulns] 1/2 Running Gitleaks secret scan on ${REPO_DIR}..."
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$REPO_DIR" --report-format json --report-path "$GITLEAKS_REPORT" --no-banner || {
    [[ "$FAIL_ON_CRITICAL" == "true" ]] && exit 1
  }
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "${REPO_DIR}:/repo:ro" -v "${OUTPUT_DIR}:/out" \
    zricethezav/gitleaks:latest detect --source /repo --report-format json --report-path "/out/gitleaks-${STAMP}.json" --no-banner || {
    [[ "$FAIL_ON_CRITICAL" == "true" ]] && exit 1
  }
else
  echo "[audit-vulns] WARN: Neither gitleaks nor docker found; skipping Gitleaks scan." >&2
fi

echo "[audit-vulns] 2/2 Running Trivy filesystem & config scan on ${REPO_DIR}..."
if command -v trivy >/dev/null 2>&1; then
  trivy fs --severity "$SEVERITY" --format json --output "$TRIVY_FS_REPORT" --exit-code "$TRIVY_EXIT_CODE" "$REPO_DIR"
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "${REPO_DIR}:/repo:ro" -v "${OUTPUT_DIR}:/out" \
    aquasec/trivy:latest fs --severity "$SEVERITY" --format json --output "/out/trivy-fs-${STAMP}.json" --exit-code "$TRIVY_EXIT_CODE" /repo
else
  echo "[audit-vulns] WARN: Neither trivy nor docker found; skipping Trivy scan." >&2
fi

echo "[audit-vulns] Zero-card audit completed. Reports in ${OUTPUT_DIR}"
