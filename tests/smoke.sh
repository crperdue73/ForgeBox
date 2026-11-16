#!/usr/bin/env bash
# ============================================================================
#  ForgeBox smoke test
#
#  Validates the product end to end without human eyes:
#    1. `docker compose config` parses (the one compose file is valid)
#    2. every expected service is present in the rendered config
#    3. no host port is published twice (fails on a real duplicate)
#    4. pins: every image uses an explicit tag, not `latest`
#    5. (optional, --up) deploy, wait on healthchecks, then hold a watch window
#
#  Usage:
#    ./tests/smoke.sh                       # config-only (fast, no deploy)
#    ./tests/smoke.sh --up                  # config + deploy core + wait healthy
#    ./tests/smoke.sh --up --profile devops
#    ./tests/smoke.sh --profile "*"         # assert every profile's service set
#
#  Note: there is no profile literally named `all`; `--profile all` is treated
#  as the wildcard `*` here for convenience, but in raw compose you must use
#  --profile "*".
#
#  Env:
#    COMPOSE_FILE   path to docker-compose.yml (default: repo root)
#    SMOKE_TIMEOUT  seconds to wait for containers to become healthy (360)
#    SMOKE_WATCH    seconds to keep watching after everything reports healthy (90)
#
#  Requires: docker + compose v2. Fails loud, exit non-zero on any failure.
#
#  Self-test: `SMOKE_SELFTEST=1 ./tests/smoke.sh` runs the port-conflict and
#  tag checks against deliberately broken fixtures to prove those checks can
#  actually fail. A test that cannot fail is not a test.
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/docker-compose.yml}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-360}"
SMOKE_WATCH="${SMOKE_WATCH:-90}"
DO_UP=0
PROFILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --up) DO_UP=1 ;;
    --profile) shift; p="$1"; [ "$p" = "all" ] && p="*"; PROFILES+=(--profile "$p") ;;
    -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

pass=0; fail=0; skip=0
ok()   { printf '\033[1;32m  PASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '\033[1;31m  FAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
skip_() { printf '\033[1;36m  SKIP\033[0m %s\n' "$*"; skip=$((skip+1)); }
head_() { printf '\n\033[1;33m== %s ==\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Host-port extraction. Works on BOTH compose spellings, because ForgeBox uses
# flow style (`ports: ["9000:9000"]`) and a future contributor may use block
# style (`- "9000:9000"`). Published host ports are what two services can
# collide on; container-internal ports collide freely and are none of our
# business.
#
# Output: "<port>:<proto>" per published port, e.g. "53:tcp", "53:udp".
# Mapping rule per entry, right to left: drop `/proto` if present; drop the
# container port; what is left is the host side. `${VAR}` (or `${VAR:-default}`)
# is resolved from .env.example (override with ENV_FILE=/path); an entry that
# cannot be resolved prints `UNRESOLVED:<entry>` so a broken default is loud
# rather than silently green. TCP and UDP are kept apart on purpose: binding the
# same number for both is legal, binding it twice for one protocol is not.
# ---------------------------------------------------------------------------
host_ports() {
  awk '
    BEGIN {
      # Emit the reference defaults as `export VAR=default` lines. awk only
      # parses; the shell evaluates, so this works on bash 3.2 (macOS) where
      # associative arrays do not exist.
      envf = ENVIRON["ENV_FILE"]
      if (envf == "") envf = ENVIRON["REPO_ROOT"] "/.env.example"
      while ((getline ln < envf) > 0) {
        line = ln
        sub(/^[[:space:]]*#?[[:space:]]*/, "", line)
        sub(/[[:space:]]*#.*/, "", line)
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
        k = line; sub(/=.*/, "", k)
        v = line; sub(/^[^=]*=/, "", v)
        gsub(/["'"'"'[:space:]]/, "", v)
        printf "export %s=%s\n", k, v
      }
    }
    # Three shapes have to be understood here, and the third is the one that
    # bit us on a real bench:
    #   short list    - "8080:80"
    #   short inline  - ports: ["8080:80"]
    #   long syntax   - - mode: ingress / target: 9000 / published: "9000"
    # `docker compose config` NORMALISES published ports to long syntax, so a
    # parser that only knows the short form finds nothing and exits 0. That is a
    # check passing on zero, which is the failure this whole file exists to
    # catch, so both shapes are parsed and both are exercised by the self-test.
    /^[[:space:]]*ports:/ {
      line = $0
      sub(/^[[:space:]]*ports:[[:space:]]*\[?/, "", line)
      sub(/\]?[[:space:]]*$/, "", line)
      if (line ~ /[^[:space:]]/) {
        n = split(line, parts, ",")
        for (i = 1; i <= n; i++) print parts[i]
        found = 1
      }
      inp = 1; next
    }
    # Long syntax, which is what `docker compose config` renders every
    # published port into. Items are split on the "- mode:" bullet; inside an
    # item the host side is `published:` and the transport is `protocol:`.
    # Bare `- 8080:80` entries still work above, so this parser reads both
    # shapes and the self-test feeds it both.
    inp && /^[[:space:]]*-[[:space:]]*mode:/ {
      if (pending != "") { printf "%s:%s\n", pending, (pending_proto == "" ? "tcp" : pending_proto); found = 1 }
      pending = ""; pending_proto = ""
      next
    }
    inp && /^[[:space:]]*published:/ {
      x = $0
      sub(/^[[:space:]]*published:[[:space:]]*/, "", x)
      gsub(/["\047[:space:]]/, "", x)
      pending = x
      next
    }
    inp && /^[[:space:]]*protocol:/ {
      x = $0
      sub(/^[[:space:]]*protocol:[[:space:]]*/, "", x)
      gsub(/["\047[:space:]]/, "", x)
      pending_proto = x
      if (pending != "") { printf "%s/%s\n", pending, (pending_proto == "" ? "tcp" : pending_proto); found = 1; pending = ""; pending_proto = "" }
      next
    }
    inp && /^[[:space:]]*target:/ { next }
    inp && /^[[:space:]]*-[[:space:]]*["\047]?[0-9$]/ { print $0; found = 1; next }
    { inp = 0; if (pending != "") { printf "%s:%s\n", pending, (pending_proto == "" ? "tcp" : pending_proto); found = 1; pending = ""; pending_proto = "" } }
    END { if (!found) exit 3 }
  ' "$1" | tr -d '"\r' | sed "s/'//g" \
    | sed -E 's/^[[:space:]]*-?[[:space:]]*//; s/[[:space:]]+$//' \
    | grep -Ev '^export |^[[:space:]]*$' \
    | while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        proto=tcp
        case "$entry" in */udp*) proto=udp ;; esac
        # strip "/proto" then the container port -> host side
        host="${entry%%/*}"
        host="${host%:*}"
        case "$host" in
          '${'*)
            name="${host#\$\{}"; name="${name%%[:-]*}"; name="${name%\}}"
            # NOTE: indirect expansion, not an associative array — this script
            # runs on macOS bash 3.2 during the DragonForge lessons, and `env`
            # is never a declared array there. Assigned only if the var exists,
            # so `set -u` stays happy either way.
            val=""
            if eval "[ \"\${$name+x}\" = x ]"; then eval "val=\"\${$name}\""; fi
            # inline default wins only when .env.example has no entry
            case "$host" in *':-'*) dflt="${host##*:-}"; dflt="${dflt%\}}"; [ -z "$val" ] && val="$dflt" ;; esac
            [ -z "$val" ] && val="UNRESOLVED:$host"
            printf '%s:%s\n' "$val" "$proto" ;;
          ''|*[!0-9]*) printf 'UNRESOLVED:%s:%s\n' "$host" "$proto" ;;
          *) printf '%s:%s\n' "$host" "$proto" ;;
        esac
      done
}

# --selftest: prove the two static checks can fail -------------------------
if [ "${SMOKE_SELFTEST:-0}" = "1" ]; then
  head_ "0. self-test: the static checks can fail"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  notest=0
  # a real collision: same host port, same protocol, flow style
  printf 'services:\n  a:\n    ports: ["9000:9000"]\n  b:\n    ports: ["9000:80"]\n' > "$tmp/dup.yml"
  if [ -n "$(host_ports "$tmp/dup.yml" | sort | uniq -d)" ]; then
    ok "port check sees a duplicate in the fixture"; notest=1
  else bad "port check MISSED a duplicate — section 3 cannot fail"; fi
  # no collision: different host ports
  printf 'services:\n  a:\n    ports: ["9000:9000"]\n  b:\n    ports: ["9001:80"]\n' > "$tmp/clean.yml"
  if [ -z "$(host_ports "$tmp/clean.yml" | sort | uniq -d)" ]; then
    ok "port check stays quiet on a clean fixture"
  else bad "port check flagged a clean file"; fi
  # block style must parse too
  printf 'services:\n  a:\n    ports:\n      - "9100:9100"\n  b:\n    ports:\n      - "9100:80"\n' > "$tmp/block.yml"
  if [ -n "$(host_ports "$tmp/block.yml" | sort | uniq -d)" ]; then
    ok "port check parses block style"
  else bad "port check MISSED a block-style duplicate"; fi
  # same number on tcp and udp is legal (DNS, WireGuard, Syncthing) — must NOT flag
  printf 'services:\n  a:\n    ports: ["53:53/tcp", "53:53/udp"]\n' > "$tmp/proto.yml"
  if [ -z "$(host_ports "$tmp/proto.yml" | sort | uniq -d)" ]; then
    ok "port check allows the same number on tcp and udp"
  else bad "port check flagged a legal tcp/udp pair"; fi
  # ${VAR} defaults must resolve, not silently vanish
  printf '%s\n' 'services:' '  a:' '    ports: ["${FB_PORT_PORTAINER:-9000}:9000"]' > "$tmp/var.yml"
  if [ "$(host_ports "$tmp/var.yml")" = "9000:tcp" ]; then
    ok "port check resolves a var default from .env.example"
  else bad "port check did not resolve the var placeholder (got: $(host_ports "$tmp/var.yml"))"; fi
  # long syntax is what `docker compose config` normalises every published port
  # into. A parser that only knows the short form finds nothing here, exits 0,
  # and the port check passes on zero — so this fixture is the one that proves
  # section 3 can still see a real file. Same content as the short fixture.
  printf '%s\n' 'services:' '  a:' '    ports:' '      - mode: ingress' '        target: 9000' '        published: "9000"' '        protocol: tcp' '  b:' '    ports:' '      - mode: ingress' '        target: 9000' '        published: "9000"' '        protocol: tcp' > "$tmp/long.yml"
  long_dup="$(host_ports "$tmp/long.yml" | sort | uniq -d)"
  if [ "$long_dup" = "9000:tcp" ]; then
    ok "port check parses long syntax and sees its duplicate"
  else bad "port check is blind to long syntax (got: $(host_ports "$tmp/long.yml" | tr '\n' ' '))"; fi
  # and tcp/udp must survive long syntax as distinct, the same way they do short
  printf '%s\n' 'services:' '  a:' '    ports:' '      - mode: ingress' '        target: 53' '        published: "53"' '        protocol: tcp' '      - mode: ingress' '        target: 53' '        published: "53"' '        protocol: udp' > "$tmp/longproto.yml"
  if [ -z "$(host_ports "$tmp/longproto.yml" | sort | uniq -d)" ]; then
    ok "port check keeps long-syntax tcp/udp apart"
  else bad "port check collapsed a long-syntax tcp/udp pair"; fi
  # tag check must see :latest
  printf 'services:\n  a:\n    image: nginx:latest\n' > "$tmp/latest.yml"
  if grep -qE 'image:[[:space:]]*[^[:space:]]+:latest' "$tmp/latest.yml"; then
    ok "tag check sees :latest in the fixture"
  else bad "tag check MISSED :latest — section 4 cannot fail"; fi
  head_ "self-test result"
  printf 'passed=%d failed=%d\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] && { printf '\033[1;32mSELFTEST OK\033[0m\n'; exit 0; } || { printf '\033[1;31mSELFTEST FAILED\033[0m\n'; exit 1; }
fi

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }

head_ "1. compose config parses"
[ -f "$COMPOSE_FILE" ] || { bad "compose file missing: $COMPOSE_FILE"; exit 1; }

# Compose requires .env for the required variables in the core profile, but a
# stranger who has just cloned the repo has not made one yet, and this is the
# moment they are most likely to run the test. If there is no .env, parse
# against the template explicitly instead of failing on a missing value: the
# quick-start already tells them to copy it. Never write a .env file here.
COMPOSE_ENV_ARGS=()
ENV_NOTE=""
if [ ! -f "$REPO_ROOT/.env" ] && [ -f "$REPO_ROOT/.env.example" ]; then
  COMPOSE_ENV_ARGS=(--env-file "$REPO_ROOT/.env.example")
  ENV_NOTE=" (no .env found: parsing against .env.example)"
fi
if rendered="$(docker compose -f "$COMPOSE_FILE" ${COMPOSE_ENV_ARGS+"${COMPOSE_ENV_ARGS[@]}"} ${PROFILES+"${PROFILES[@]}"} config 2>/dev/null)"; then
  ok "docker compose config -> valid (${#rendered} bytes)${ENV_NOTE}"
else
  bad "docker compose config failed${ENV_NOTE}"; docker compose -f "$COMPOSE_FILE" ${COMPOSE_ENV_ARGS+"${COMPOSE_ENV_ARGS[@]}"} config || true; exit 1
fi

head_ "2. expected services present"
# Core is always expected; profile services are expected only when their
# profile is selected. Keep this list in sync with docker-compose.yml.
# watchtower is NOT core: it lives in the `autoupdate` profile on purpose (see
# the comment in docker-compose.yml). It appears here only under its own
# profile, so listing it in both places made a core-only run expect a service
# compose correctly refuses to define.
CORE="portainer heimdall npm uptime-kuma glances"
declare -A EXTRA=(
  [security]="pihole wireguard vaultwarden"
  [vpn]="gluetun"
  [devops]="gitea semaphore jenkins code-server guacamole"
  [media]="jellyfin sonarr radarr prowlarr qbittorrent overseerr"
  [productivity]="homeassistant paperless-ngx paperless_redis paperless_db vikunja linkding n8n"
  [files]="nextcloud syncthing chibisafe"
  [autoupdate]="watchtower"
)
expected="$CORE"
sel_profiles=""
ALL_PROFILES="${!EXTRA[*]}"
for ((i=0;i<${#PROFILES[@]};i+=2)); do
  p="${PROFILES[$((i+1))]}"
  # `--profile '*'` (or a bare `all`) means every profile — this mirrors what
  # Docker actually does. Gluetun needs a host /dev/net/tun node, so on a host
  # without it the wildcard deploy will error on gluetun alone (see
  # docs/troubleshooting.md); run smoke with an explicit profile list on such hosts.
  if [ "$p" = "*" ] || [ "$p" = "all" ]; then
    for ep in $ALL_PROFILES; do sel_profiles+="$ep "; expected+=" ${EXTRA[$ep]}"; done
  else
    sel_profiles+="$p "; expected+=" ${EXTRA[$p]:-}"
  fi
done
expected="$(echo $expected | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')"
# The rendered config is `services:` only (compose drops everything else), so a
# 2-space-indented key is exactly a service definition. An awk map beats a
# regex here — service names contain hyphens and underscores.
svc_list="$(printf '%s\n' "$rendered" | awk '
  /^services:[[:space:]]*$/ { ins = 1; next }
  /^[^[:space:]]/ { ins = 0 }
  ins && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { k = $0; sub(/^  /, "", k); sub(/:.*/, "", k); print k }
')"
for c in $expected; do
  if printf '%s\n' "$svc_list" | grep -qx "$c"; then
    ok "service '$c' defined"
  else bad "service '$c' MISSING"; fi
done
echo "    (profiles selected: ${sel_profiles:-core only})"

head_ "3. no host port published twice"
# Uses the rendered config (ports substituted from .env), so a collision caused
# by overridden FB_PORT_* values is caught, not just one in the defaults.
# Read the rendered config: `${FB_PORT_X}` is already substituted there, so a
# collision created by an override in .env is caught, not just one in the
# defaults. host_ports still handles the ${VAR} form for the fixture self-test.
rendered_tmp="$(mktemp)"
trap 'rm -f "$rendered_tmp"' EXIT
printf '%s\n' "$rendered" > "$rendered_tmp"
# `|| true`: upstream functions can return non-zero (host_ports exits 3 when it
# finds no ports), and under `set -e` an bare assignment from a pipeline that
# fails would kill the run before this check could report anything.
distinct_ports="$(host_ports "$rendered_tmp" | sort -u | wc -l | tr -d ' ' || true)"
[ -n "$distinct_ports" ] || distinct_ports=0
dupes="$(host_ports "$rendered_tmp" | sort | uniq -d || true)"
total_entries="$(host_ports "$rendered_tmp" | wc -l | tr -d ' ' || true)"
[ -n "$total_entries" ] || total_entries=0
# A zero here is not a pass. Either the stack genuinely publishes nothing (it
# does not: core alone publishes several, the full profile set dozens), or the
# render we were handed carries no `ports:` blocks and this check is measuring
# nothing while printing green. Say which, and fail on the second.
if [ "$distinct_ports" -eq 0 ]; then
  bad "port check saw 0 published ports: nothing to check, so this is not a pass"
  echo "      the rendered config carries no ports; check that 'docker compose config' actually ran"
elif [ -z "$dupes" ]; then
  # Two numbers on purpose: the same host port stated for tcp and for udp is
  # legal and counts twice in the entry tally (pihole 53, syncthing 22000), so a
  # bare count invites "which number is right" instead of an answer. Say both.
  ok "no duplicate host ports ($total_entries published entries across $distinct_ports distinct host port numbers)"
else
  bad "duplicate host ports: $(echo $dupes | tr '\n' ' ') ($distinct_ports distinct published)"
  for d in $dupes; do
    port="${d%%:*}"
    # name the services that publish it, so a failure points at a file line
    # NB: use grep -F, not awk index(). mawk 1.3.4 returns 0 for needles like
    # "9000:" preceded by "}" — a real bug that would silently blank this line.
    where="$(awk '
      /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { svc = $0; sub(/^  /, "", svc); sub(/:.*/, "", svc) }
      { print NR "\t" svc "\t" $0 }
    ' "$COMPOSE_FILE" | grep -F -- "$port:" | awk -F'\t' '{ printf "%s (line %s) ", $2, $1 }')"
    echo "      $d -> ${where:-not found in compose file}"
  done
fi

head_ "4. image tags are pinned"
# `:latest` is a defect by default, but one pin is deliberate and argued for in
# the compose comments: Nginx Proxy Manager tracks `latest` because 2.16.0 booted
# with a green :81 healthcheck and never finished admin init. Exemptions are
# listed here explicitly and reported out loud, so an accidental new `:latest`
# still fails while a decision this file already explains does not.
LATEST_ALLOWED="jc21/nginx-proxy-manager:latest"
# grep exits 1 on no-match, so capture then test the string (not the exit code)
latest_all="$(grep -oE '^[[:space:]]*image:[[:space:]]*[^[:space:]]+:[^[:space:]]*latest[^[:space:]]*' "$COMPOSE_FILE" | sed -E 's/.*image:[[:space:]]*//' || true)"
pinned_bad=""
for img in $latest_all; do
  case " $LATEST_ALLOWED " in
    *" $img "*) continue ;;
  esac
  pinned_bad+="$img "
done
if [ -n "$pinned_bad" ]; then
  bad "unpinned \`:latest\` images: $pinned_bad"
else
  ok "no unintended \`:latest\` image tags ($(grep -cE '^[[:space:]]*image:' "$COMPOSE_FILE") images)"
  [ -n "$latest_all" ] && echo "    (deliberate: $LATEST_ALLOWED, see docker-compose.yml)"
fi

if [ "$DO_UP" -eq 1 ]; then
  head_ "5. deploy, wait for healthy, then hold"
  # --wait blocks until every container is running *and* healthy, or fails.
  # Services with no healthcheck (docs/healthchecks.md lists them) count as
  # ready once running — their absence is documented, not accidental.
  #
  # npm is deliberately not gated here. Its first boot chowns the certbot
  # site-packages tree inside an s6 prepare oneshot, and that walk ran >624s on
  # a clean bench with no fixed duration. `up --wait` has no "wait, but not on
  # this one" — it either gates on every healthcheck or on none — so npm is
  # started first without --wait and verified after. Without this, a stranger's
  # very first command prints FAILED about a container that is mid-install and
  # finishes fine.
  # Start everything detached, no gate.
  if ! docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} up --detach; then
    bad "compose up --detach failed"
  else
    ok "compose up --detach completed"
  fi
  # Now gate on everything except npm.
  gated_list=""
  svc_count=0
  for svc in $(docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} config --services 2>/dev/null); do
    [ "$svc" = "npm" ] && continue
    gated_list="$gated_list $svc"; svc_count=$((svc_count + 1))
  done
  if [ "$svc_count" -eq 0 ]; then
    bad "no services found to gate on"
  elif docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} up --detach --wait --wait-timeout "$SMOKE_TIMEOUT" $gated_list; then
    ok "compose up --wait completed within ${SMOKE_TIMEOUT}s ($svc_count gated services, npm excluded by design)"
  else
    bad "compose up --wait failed or timed out"; docker compose -f "$COMPOSE_FILE" ps || true
  fi

  # Names come from the project itself, never from `container_name:` (ForgeBox
  # deliberately removed those so two labs can coexist).
  proj="$(docker compose -f "$COMPOSE_FILE" config --format json 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  ids="$(docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} ps --quiet || true)"
  if [ -z "$ids" ]; then
    bad "no containers found after deploy"
  else
    for id in $ids; do
      read -r name status health <<<"$(docker inspect -f '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" | sed 's|^/||')"
      if [ "$status" != "running" ]; then bad "$name state=$status"
      elif [ "$health" = "unhealthy" ]; then bad "$name unhealthy"
      elif [ "$health" = "starting" ] && [ "$(printf '%s' "$name" | sed -E 's/^.*-npm-[0-9]+$//; s/^npm$//')" = "" ]; then
        # expected on a first boot, not a defect: unbounded init, see docker-compose.yml
        ok "$name starting (first-boot init, not gated)"
      elif [ "$health" = "starting" ]; then bad "$name still starting after --wait"
      else ok "$name running/$health"; fi
    done
  fi

  # Watch window: a container that goes healthy and then dies on its first real
  # request is invisible to `up --wait`. Hold, then re-read.
  if ids="$(docker compose -f "$COMPOSE_FILE" ${PROFILES+"${PROFILES[@]}"} ps --quiet 2>/dev/null)" && [ -n "$ids" ]; then
    echo "    watching for ${SMOKE_WATCH}s (a container that dies after healthy shows up here)"
    sleep "$SMOKE_WATCH"
    for id in $ids; do
      read -r name status health <<<"$(docker inspect -f '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" | sed 's|^/||')"
      case "$status/$health" in
        running/unhealthy) bad "$name went unhealthy during the watch window" ;;
        running/*) : ;;
        *) bad "$name died during the watch window (state=$status)" ;;
      esac
    done
    [ "$fail" -eq 0 ] && ok "everything still up after ${SMOKE_WATCH}s"
  fi
fi

head_ "result"
# Four counters, always. Nine and eight wear the same value if you only publish
# the ones that fired, so the total executed is printed next to them.
printf 'executed=%d passed=%d failed=%d skipped=%d\n' "$((pass+fail+skip))" "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && { printf '\033[1;32mSMOKE OK\033[0m\n'; exit 0; } || { printf '\033[1;31mSMOKE FAILED\033[0m\n'; exit 1; }
