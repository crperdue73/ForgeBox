#!/usr/bin/env bash
# ============================================================================
#  ForgeBox smoke test
#
#  Validates the product end to end without human eyes:
#    1. `docker compose config` parses (the one compose file is valid)
#    2. every expected service is present in the rendered config
#    3. (optional, --up) bring the core profile up and wait for healthchecks
#
#  Usage:
#    ./tests/smoke.sh            # config-only (fast, no deploy)
#    ./tests/smoke.sh --up       # config + deploy core + wait for health
#    ./tests/smoke.sh --up --profile devops
#
#  Env:
#    COMPOSE_FILE   path to docker-compose.yml (default: repo root)
#    SMOKE_TIMEOUT  seconds to wait for containers to become healthy (60)
#
#  Requires: docker + compose v2. Fails loud, exit non-zero on any failure.
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/docker-compose.yml}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-60}"
DO_UP=0
PROFILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --up) DO_UP=1 ;;
    --profile) shift; PROFILES+=(--profile "$1") ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

pass=0; fail=0
ok()   { printf '\033[1;32m  PASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '\033[1;31m  FAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
head_() { printf '\n\033[1;33m== %s ==\033[0m\n' "$*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }

head_ "1. compose config parses"
[ -f "$COMPOSE_FILE" ] || { bad "compose file missing: $COMPOSE_FILE"; exit 1; }
if rendered="$(docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} config 2>/dev/null)"; then
  ok "docker compose config -> valid (${#rendered} bytes)"
else
  bad "docker compose config failed"; docker compose -f "$COMPOSE_FILE" config || true; exit 1
fi

head_ "2. expected services present"
# Core is always expected; profile services are expected only when their
# profile is selected. Keep this list in sync with docker-compose.yml.
CORE="portainer heimdall npm uptime-kuma watchtower glances"
declare -A EXTRA=(
  [security]="pihole wireguard vaultwarden gluetun"
  [devops]="gitea semaphore jenkins code-server guacamole"
  [media]="jellyfin sonarr radarr prowlarr qbittorrent overseerr"
  [productivity]="homeassistant paperless-ngx paperless_redis paperless_db vikunja linkding n8n"
  [files]="nextcloud syncthing chibisafe"
)
expected="$CORE"
sel_profiles=""
for ((i=0;i<${#PROFILES[@]};i+=2)); do p="${PROFILES[$((i+1))]}"; sel_profiles+="$p "; expected+=" ${EXTRA[$p]:-}"; done
for c in $expected; do
  if grep -qE "^  ${c}:" <<<"$rendered"; then ok "service '$c' defined"; else bad "service '$c' MISSING"; fi
done
echo "    (profiles selected: ${sel_profiles:-core only})"

head_ "3. port map has no internal conflicts"
dupes="$(grep -oE '^\s+- "[0-9]+:[0-9]+' <<<"$rendered" | sed -E 's/.*"([0-9]+):.*/\1/' | sort | uniq -d || true)"
if [ -z "$dupes" ]; then ok "no duplicate host ports"; else bad "duplicate host ports: $(echo $dupes | tr '\n' ' ')"; fi

if [ "$DO_UP" -eq 1 ]; then
  head_ "4. bring up + wait for healthy"
  docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} up -d
  deadline=$(( $(date +%s) + SMOKE_TIMEOUT ))
  # Collect expected *started* container names from the rendered config
  names="$(grep -oE 'container_name: .*' <<<"$rendered" | awk '{print $2}')"
  while :; do
    all_ok=1
    for n in $names; do
      st="$(docker inspect -f '{{.State.Status}}' "$n" 2>/dev/null || echo missing)"
      case "$st" in running) : ;; *) all_ok=0 ;; esac
    done
    [ "$all_ok" -eq 1 ] && break
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 3
  done
  for n in $names; do
    st="$(docker inspect -f '{{.State.Status}}' "$n" 2>/dev/null || echo missing)"
    if [ "$st" = "running" ]; then ok "$n running"; else bad "$n state=$st"; fi
  done
fi

head_ "result"
printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { printf '\033[1;32mSMOKE OK\033[0m\n'; exit 0; } || { printf '\033[1;31mSMOKE FAILED\033[0m\n'; exit 1; }
