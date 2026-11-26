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
)

printf "%-14s %-8s %-6s %-10s %s\n" "SERVICE" "STATUS" "HTTP" "LATENCY" "ENDPOINT"
printf "%-14s %-8s %-6s %-10s %s\n" "--------------" "--------" "------" "----------" "----------------------------------"

ok_count=0
total_count="${#SERVICES[@]}"

for entry in "${SERVICES[@]}"; do
  name="${entry%%|*}"
  base_url="${entry#*|}"
  endpoint="${base_url%/}/health"

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

  printf "%-14s %-8s %-6s %-10s %s\n" "$name" "$status" "$http_code" "$latency_ms" "$endpoint"
done

echo ""
echo "Fleet Health Summary: ${ok_count}/${total_count} OK"
if [[ "$ok_count" -lt "$total_count" ]]; then
  exit 1
fi
