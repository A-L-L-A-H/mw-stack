#!/usr/bin/env bash
set -euo pipefail

HOST="${MW_VERIFY_HOST:-127.0.0.1}"
TIMEOUT_SEC="${MW_VERIFY_TIMEOUT:-3}"

declare -a SERVICES=(
  "mw-echo|${MW_ECHO_URL:-http://${HOST}:${MW_ECHO_PORT:-4310}}"
  "mw-lab|${MW_LAB_URL:-http://${HOST}:${MW_LAB_PORT:-4400}}"
  "mw-mission|${MW_MISSION_URL:-http://${HOST}:${MW_MISSION_PORT:-4410}}"
  "mw-dock|${MW_DOCK_URL:-http://${HOST}:${MW_DOCK_PORT:-3000}}"
  "mw-design|${MW_DESIGN_URL:-http://${HOST}:${MW_DESIGN_PORT:-8080}}"
  "mw-isp|${MW_ISP_URL:-http://${HOST}:${MW_ISP_PORT:-8091}}"
  "mw-cp|${MW_CP_URL:-http://${HOST}:${MW_CP_PORT:-4440}}"
  "mw-corpus|${MW_CORPUS_URL:-http://${HOST}:${MW_CORPUS_PORT:-4420}}"
  "mw-nexus|${MW_NEXUS_URL:-http://${HOST}:${MW_NEXUS_PORT:-4430}}"
  "mw-lore|${MW_LORE_URL:-http://${HOST}:${MW_LORE_PORT:-4450}}"
  "mw-mylove|${MW_MYLOVE_URL:-http://${HOST}:${MW_MYLOVE_PORT:-4460}}"
  "mw-studio|${MW_STUDIO_URL:-http://${HOST}:${MW_STUDIO_PORT:-4470}}"
  "mw-rid|${MW_RID_URL:-http://${HOST}:${MW_RID_PORT:-4480}}"
  "mw-rocksoul-gateway|${MW_ROCKSOUL_GATEWAY_URL:-http://${HOST}:${MW_ROCKSOUL_GATEWAY_PORT:-4510}}"
  "mw-rocksoul-core|${MW_ROCKSOUL_CORE_URL:-http://${HOST}:${MW_ROCKSOUL_CORE_PORT:-4520}}"
  "mw-rocksoul-mcp|${MW_ROCKSOUL_MCP_URL:-http://${HOST}:${MW_ROCKSOUL_MCP_PORT:-4530}}"
  "mw-rocksoul-sandbox|${MW_ROCKSOUL_SANDBOX_URL:-http://${HOST}:${MW_ROCKSOUL_SANDBOX_PORT:-4540}}"
)

declare -a CONTRACTS=(
  "mw-rid-oidc|${MW_RID_URL:-http://${HOST}:${MW_RID_PORT:-4480}}/.well-known/openid-configuration"
  "mw-rid-jwks|${MW_RID_URL:-http://${HOST}:${MW_RID_PORT:-4480}}/jwks"
  "mw-dock-realtime|${MW_DOCK_URL:-http://${HOST}:${MW_DOCK_PORT:-3000}}/api/v1/dock/realtime"
)

printf "%-20s %-8s %-6s %-10s %s\n" "SERVICE" "STATUS" "HTTP" "LATENCY" "ENDPOINT"
printf "%-20s %-8s %-6s %-10s %s\n" "--------------------" "--------" "------" "----------" "----------------------------------"

ok_count=0
total_count=$(( ${#SERVICES[@]} + ${#CONTRACTS[@]} + 2 ))

probe_endpoint() {
  local name="$1"
  local endpoint="$2"
  local probe_out http_code time_sec latency_ms status

  probe_out="$(curl -sS -o /dev/null --connect-timeout "$TIMEOUT_SEC" --max-time "$TIMEOUT_SEC" -w "%{http_code} %{time_total}" "$endpoint" 2>/dev/null || echo "000 0.000")"
  http_code="${probe_out%% *}"
  time_sec="${probe_out#* }"
  latency_ms="$(awk -v t="$time_sec" 'BEGIN { printf "%.0fms", t * 1000 }')"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    status="OK"
    ok_count=$((ok_count + 1))
  else
    status="DOWN"
    [[ "$http_code" == "000" ]] && http_code="-"
  fi

  printf "%-20s %-8s %-6s %-10s %s\n" "$name" "$status" "$http_code" "$latency_ms" "$endpoint"
}

probe_contract_body() {
  local name="$1"
  local endpoint="$2"
  local pattern="$3"
  local body http_code time_sec latency_ms status

  body="$(curl -sS --connect-timeout "$TIMEOUT_SEC" --max-time "$TIMEOUT_SEC" -w $'\n%{http_code} %{time_total}' "$endpoint" 2>/dev/null || true)"
  if [[ -z "$body" ]]; then
    printf "%-20s %-8s %-6s %-10s %s\n" "$name" "DOWN" "-" "-" "$endpoint"
    return
  fi

  http_code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  time_sec="${http_code#* }"
  http_code="${http_code%% *}"
  latency_ms="$(awk -v t="$time_sec" 'BEGIN { printf "%.0fms", t * 1000 }')"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && printf '%s' "$body" | grep -Eq "$pattern"; then
    status="OK"
    ok_count=$((ok_count + 1))
  else
    status="DOWN"
    [[ "$http_code" == "000" ]] && http_code="-"
  fi

  printf "%-20s %-8s %-6s %-10s %s\n" "$name" "$status" "$http_code" "$latency_ms" "$endpoint"
}

probe_realtime_contract() {
  local name="mw-dock-realtime-contract"
  local base_url="${MW_DOCK_URL:-http://${HOST}:${MW_DOCK_PORT:-3000}}"
  local endpoint="${base_url%/}/api/v1/dock/realtime"
  local probe_out http_code content_type time_sec latency_ms status

  # A bounded GET verifies SSE headers without needing a token.
  probe_out="$(curl -sS -N --max-time "$TIMEOUT_SEC" -D - -o /dev/null \
    --connect-timeout "$TIMEOUT_SEC" \
    -w $'\n%{http_code} %{content_type} %{time_total}' "$endpoint" 2>/dev/null || true)"
  if [[ -z "$probe_out" ]]; then
    printf "%-20s %-8s %-6s %-10s %s\n" "$name" "DOWN" "-" "-" "$endpoint"
    return
  fi

  http_code="${probe_out##*$'\n'}"
  probe_out="${probe_out%$'\n'*}"
  time_sec="${http_code##* }"
  content_type="${http_code% *}"
  content_type="${content_type#* }"
  http_code="${http_code%% *}"
  latency_ms="$(awk -v t="$time_sec" 'BEGIN { printf "%.0fms", t * 1000 }')"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] &&
     printf '%s' "$probe_out" | grep -Eqi '^content-type:[[:space:]]*text/event-stream' &&
     printf '%s' "$content_type" | grep -Eq '^text/event-stream' &&
     printf '%s' "$probe_out" | grep -Eqi '^cache-control:[[:space:]]*no-cache'; then
    status="OK"
    ok_count=$((ok_count + 1))
  else
    status="DOWN"
    [[ "$http_code" == "000" ]] && http_code="-"
  fi

  printf "%-20s %-8s %-6s %-10s %s\n" "$name" "$status" "$http_code" "$latency_ms" "$endpoint"
}

for entry in "${SERVICES[@]}"; do
  name="${entry%%|*}"
  base_url="${entry#*|}"
  probe_endpoint "$name" "${base_url%/}/health"
done

for entry in "${CONTRACTS[@]}"; do
  name="${entry%%|*}"
  endpoint="${entry#*|}"
  probe_endpoint "$name" "$endpoint"
done

rid_base="${MW_RID_URL:-http://${HOST}:${MW_RID_PORT:-4480}}"
probe_contract_body "mw-rid-oidc-contract" "${rid_base%/}/.well-known/openid-configuration" '"issuer"[[:space:]]*:[[:space:]]*"[^"]+"|"jwks_uri"[[:space:]]*:[[:space:]]*"[^"]+"'
probe_contract_body "mw-rid-jwks-contract" "${rid_base%/}/jwks" '"keys"[[:space:]]*:[[:space:]]*\['
probe_realtime_contract

echo ""
echo "Fleet Health Summary: ${ok_count}/${total_count} OK"
if [[ "$ok_count" -lt "$total_count" ]]; then
  exit 1
fi
