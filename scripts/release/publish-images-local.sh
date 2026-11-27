#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${MW_DOCKER_REGISTRY:-ghcr.io/a-l-l-a-h}"
TAG="${MW_IMAGE_TAG:-latest}"
REPO_ROOT="${MW_REPO_ROOT:-/opt/mw-repos}"
if [[ ! -d "$REPO_ROOT" && -d "Z:/repo" ]]; then
  REPO_ROOT="Z:/repo"
elif [[ ! -d "$REPO_ROOT" && -d "/z/repo" ]]; then
  REPO_ROOT="/z/repo"
fi

DRY_RUN=0
DO_PUSH=0
declare -a TARGET_SERVICES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --push) DO_PUSH=1; shift ;;
    --tag) TAG="${2:-latest}"; shift 2 ;;
    --registry) REGISTRY="${2:-ghcr.io/a-l-l-a-h}"; shift 2 ;;
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    *) TARGET_SERVICES+=("$1"); shift ;;
  esac
done

ALL_SERVICES=(
  "mw-echo"
  "mw-rid"
  "mw-dock"
  "mw-xv"
  "mw-design"
  "mw-mylove"
  "mw-lab"
  "mw-mission"
  "mw-isp"
  "mw-cp"
  "mw-corpus"
  "mw-nexus"
  "mw-lore"
  "mw-studio"
  "mw-rocksoul-gateway"
  "mw-rocksoul-core"
  "mw-rocksoul-mcp"
  "mw-rocksoul-sandbox"
)

if [[ ${#TARGET_SERVICES[@]} -eq 0 ]]; then
  TARGET_SERVICES=("${ALL_SERVICES[@]}")
fi

echo "=== MoonWitness Zero-Card Local Docker Publisher ==="
echo "Registry:  $REGISTRY"
echo "Tag:       $TAG"
echo "DryRun:    $DRY_RUN"
echo "Push:      $DO_PUSH"
echo "RepoRoot:  $REPO_ROOT"
echo "Services:  ${TARGET_SERVICES[*]}"
echo ""

success_count=0
skipped_count=0

for svc in "${TARGET_SERVICES[@]}"; do
  svc_dir="${REPO_ROOT}/${svc}"
  dockerfile="${svc_dir}/Dockerfile"
  image_name="${REGISTRY}/${svc}:${TAG}"

  if [[ ! -f "$dockerfile" ]]; then
    echo "[$svc] WARN: Skipping, no Dockerfile at $dockerfile"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  echo "[$svc] Building $image_name from $svc_dir..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY-RUN] docker build -t $image_name $svc_dir"
    if [[ "$DO_PUSH" -eq 1 ]]; then
      echo "  [DRY-RUN] docker push $image_name"
    fi
    success_count=$((success_count + 1))
  else
    docker build -t "$image_name" "$svc_dir"
    if [[ "$DO_PUSH" -eq 1 ]]; then
      echo "[$svc] Pushing $image_name..."
      docker push "$image_name"
    fi
    success_count=$((success_count + 1))
  fi
done

echo ""
echo "Publishing Summary: ${success_count} built/verified, ${skipped_count} skipped."
