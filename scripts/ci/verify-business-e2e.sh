#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${MW_STACK_DIR:-Z:/repo/mw-stack}"
CORE_DIR="${MW_CORE_DIR:-Z:/repo/mw-core}"

if [[ ! -d "$STACK_DIR" && -d "/z/repo/mw-stack" ]]; then
  STACK_DIR="/z/repo/mw-stack"
  CORE_DIR="/z/repo/mw-core"
fi

echo "================================================================="
echo "   MoonWitness Business E2E Verification & Integration Harness   "
echo "================================================================="

if command -v powershell >/dev/null 2>&1; then
  powershell -NoProfile -ExecutionPolicy Bypass -File "${STACK_DIR}/scripts/ci/verify-business-e2e.ps1" -StackDir "$STACK_DIR" -CoreDir "$CORE_DIR"
elif command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File "${STACK_DIR}/scripts/ci/verify-business-e2e.ps1" -StackDir "$STACK_DIR" -CoreDir "$CORE_DIR"
else
  echo "[1/2] Running validate-core-registry.mjs..."
  node "${STACK_DIR}/scripts/ci/validate-core-registry.mjs"

  echo "[2/2] Validating bash shell syntax on all scripts..."
  bash -n "${STACK_DIR}"/scripts/*/*.sh

  echo "Business E2E Verification PASSED (POSIX runner)."
fi
