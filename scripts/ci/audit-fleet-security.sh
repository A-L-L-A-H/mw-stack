#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${MW_REPO_ROOT:-Z:/repo}"
if [[ ! -d "$REPO_ROOT" && -d "/z/repo" ]]; then
  REPO_ROOT="/z/repo"
fi

OUTPUT_PATH="${1:-}"

echo "=== MoonWitness Fleet Security & Invariant Audit ==="

# Execute node/python or powershell if available, or direct grep
if command -v powershell >/dev/null 2>&1; then
  if [[ -n "$OUTPUT_PATH" ]]; then
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/audit-fleet-security.ps1" -RepoRoot "$REPO_ROOT" -OutputPath "$OUTPUT_PATH"
  else
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/audit-fleet-security.ps1" -RepoRoot "$REPO_ROOT"
  fi
elif command -v pwsh >/dev/null 2>&1; then
  if [[ -n "$OUTPUT_PATH" ]]; then
    pwsh -NoProfile -File "$(dirname "$0")/audit-fleet-security.ps1" -RepoRoot "$REPO_ROOT" -OutputPath "$OUTPUT_PATH"
  else
    pwsh -NoProfile -File "$(dirname "$0")/audit-fleet-security.ps1" -RepoRoot "$REPO_ROOT"
  fi
else
  # Minimal fallback in bash
  echo "Scanning $REPO_ROOT for forbidden ORM imports..."
  orm_violations=$(grep -rnE "@moonwitness/orm-[a-z0-9-]*" "$REPO_ROOT"/mw-rocksoul-* 2>/dev/null || true)
  if [[ -n "$orm_violations" ]]; then
    echo "ERROR: Zero-ORM invariant violated:" >&2
    echo "$orm_violations" >&2
    exit 1
  fi
  echo "Audit OK (Bash fallback): Zero ORM imports in mw-rocksoul-*."
fi
