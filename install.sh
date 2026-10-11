#!/usr/bin/env bash
# ============================================================================
#  ForgeBox installer — turn a fresh Debian/Ubuntu host into a datacenter host.
#  Idempotent: safe to run more than once. Fails loud.
#
#    sudo bash install.sh
#    sudo bash install.sh --unattended          # no prompts; auto-seed .env
#    sudo bash install.sh --answers my.env      # seed .env from an answers file
#    sudo bash install.sh --deploy              # ...and run `docker compose up -d`
#
#  It will: install Docker Engine + Compose v2 + git, create host dirs,
#  optionally seed `.env` from an answers file (auto-generating any remaining
#  `change-me` secrets), and print the exact next command. By default it does
#  NOT deploy containers — that is done with `docker compose up -d` so you stay
#  in control. Pass --deploy for a fully unattended host bring-up.
# ============================================================================
set -euo pipefail

log()  { printf '\033[1;33m[forgebox]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[forgebox]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[forgebox] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Args (unattended / answer file) ---------------------------------------
UNATTENDED=0
ANSWERS_FILE=""
DO_DEPLOY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--unattended) UNATTENDED=1 ;;
    --answers) shift; [ $# -gt 0 ] || die "--answers needs a file path"; ANSWERS_FILE="$1" ;;
    --answers=*) ANSWERS_FILE="${1#--answers=}" ;;
    --deploy) DO_DEPLOY=1 ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[ -n "$ANSWERS_FILE" ] && UNATTENDED=1

[ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."

# --- OS check ---------------------------------------------------------------
if [ -r /etc/os-release ]; then . /etc/os-release; fi
case "${ID:-}" in
  debian|ubuntu|raspbian) : ;;
  *) log "Untested distro '${ID:-unknown}' — continuing, but Debian/Ubuntu is supported." ;;
esac
log "Host: ${PRETTY_NAME:-unknown} $(uname -m)"

# --- 1. Base tooling --------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
log "Installing base tooling (ca-certificates curl gnupg git)..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg git

# --- 2. Docker Engine + Compose v2 -----------------------------------------
if command -v docker >/dev/null 2>&1; then
  ok "Docker already installed: $(docker --version)"
else
  log "Installing Docker Engine + Compose plugin..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID:-debian}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID:-debian} ${VERSION_CODENAME:-bookworm} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ok "Docker installed: $(docker --version)"
fi

systemctl enable --now docker
ok "docker service: $(systemctl is-active docker)"

# --- 3. Host directories ----------------------------------------------------
log "Creating host directories..."
install -d -m 0755 /opt/forgebox
install -d -m 0755 /opt/forgebox/data/media /opt/forgebox/data/consume
ok "Host dirs ready under /opt/forgebox"

# --- 4. Kernel tweaks for the media/networking stack ------------------------
# Best-effort: on unprivileged LXC/containers some keys are read-only and
# `sysctl --system` returns non-zero. That must NOT abort the installer.
log "Applying sysctl tweaks (inotify limits for media stack)..."
cat > /etc/sysctl.d/99-forgebox.conf <<'SYSCTL'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
net.ipv4.conf.all.src_valid_mark = 1
SYSCTL
if sysctl --system >/dev/null 2>&1; then
  ok "sysctl tweaks applied"
else
  log "WARN: some sysctl keys could not be set (common in LXC/containers);"
  log "      ForgeBox will still run — media/network tuning is best-effort."
fi

# --- 5. Firewall hint -------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  log "UFW is active. ForgeBox needs ports opened for the services you deploy."
  log "See docs/services.md for the full port table, then e.g.:"
  log "  ufw allow 8080/tcp  # Heimdall dashboard"
fi

# --- 6. Answer file / unattended .env seeding -------------------------------
# If invoked unattended (or with --answers), materialise `.env` in the CWD from
# `.env.example` + the supplied answers, auto-generating any secret still set
# to `change-me`. Idempotent: an existing `.env` is never clobbered; only
# unresolved secrets are filled in.
gen_secret() { openssl rand -hex 32 2>/dev/null || head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

seed_env() {
  local dir="$1"
  local example="$dir/.env.example"
  local envf="$dir/.env"
  local key="" line="" tmp=""
  [ -f "$example" ] || { log "No .env.example in $dir — skipping .env seeding."; return 0; }

  # Precedence: existing .env  <  .env.example  <  answers file
  [ -f "$envf" ] || cp "$example" "$envf"
  if [ -n "$ANSWERS_FILE" ]; then
    [ -r "$ANSWERS_FILE" ] || die "Answers file not readable: $ANSWERS_FILE"
    while IFS= read -r line; do
      case "$line" in ''|'#'*) continue ;; esac
      key="${line%%=*}"
      case "$key" in ''|*[!A-Za-z0-9_]*) continue ;; esac
      if grep -q "^${key}=" "$envf"; then
        tmp="$(mktemp)"; sed "s|^${key}=.*|${line}|" "$envf" > "$tmp" && mv "$tmp" "$envf"
      else
        printf '%s\n' "$line" >> "$envf"
      fi
    done < "$ANSWERS_FILE"
    ok "Seeded .env from answers file: $ANSWERS_FILE"
  fi

  # Auto-generate any remaining placeholder secrets (unattended bring-up).
  local k
  for k in PAPERLESS_DBPASS PAPERLESS_SECRET_KEY N8N_ENCRYPTION_KEY PIHOLE_PASSWORD SEMAPHORE_ADMIN_PASSWORD CODE_SERVER_PASSWORD; do
    if grep -q "^${k}=change-me\$" "$envf"; then
      tmp="$(mktemp)"; sed "s|^${k}=.*|${k}=$(gen_secret)|" "$envf" > "$tmp" && mv "$tmp" "$envf"
      ok "Generated secret for ${k}"
    fi
  done
  chmod 600 "$envf"

  # A filled key is only truly missing if VPN creds are blank — warn, don't fail.
  if grep -qE '^WIREGUARD_PRIVATE_KEY=$' "$envf"; then
    log "WARN: WIREGUARD_PRIVATE_KEY is empty — Gluetun/qBittorrent VPN media downloads stay disabled until set."
  fi
}

if [ "$UNATTENDED" -eq 1 ] || [ -n "$ANSWERS_FILE" ]; then
  seed_env "$(pwd)"
fi

ok "Done."
echo
if [ "$DO_DEPLOY" -eq 1 ]; then
  [ -f ./docker-compose.yml ] || die "--deploy given but no docker-compose.yml in $(pwd)"
  log "Unattended deploy: docker compose up -d"
  docker compose up -d
  ok "Stack deployed. Check status with: docker compose ps"
  echo
fi
ok "Next steps:"
echo "  1) cd /opt/forgebox   (copy docker-compose.yml + .env here, or clone the repo)"
echo "  2) cp .env.example .env && \$EDITOR .env"
echo "  3) docker compose up -d"
echo "  For an unattended host, re-run: sudo bash install.sh --unattended --deploy"
echo
