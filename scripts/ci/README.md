# CI & Verification Scripts

Rule 16 canonical bucket for fleet auditing, registry validation, and E2E verification scripts.

- `audit-fleet-security.{sh,ps1}` — Fleet ORM and security posture audit
- `audit-vulns-zero-card.sh` — Zero-card Gitleaks + Trivy vulnerability audit
- `validate-core-registry.mjs` — Validates `mw-core/registry/` schema and invariants
- `verify-business-e2e.{sh,ps1}` — Business VPS end-to-end verification
- `verify-fleet.{sh,ps1}` — Fleet health verification
- `verify-rocksoul-e2e.ps1` — Rocksoul E2E verification
