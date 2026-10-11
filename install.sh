#!/usr/bin/env bash
# ============================================================================
#  ForgeBox installer — turn a fresh Debian/Ubuntu host into a datacenter host.
#  Idempotent: safe to run more than once. Fails loud.
#
#    sudo bash install.sh
#
#  It will: install Docker Engine + Compose v2 + git, create host dirs,
#  and print the exact next command. It does NOT deploy containers — that is
#  done with `docker compose up -d` so you stay in control.
# ============================================================================
set -euo pipefail

log()  { printf '\033[1;33m[forgebox]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[forgebox]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[forgebox] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

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
log "Applying sysctl tweaks (inotify limits for media stack)..."
cat > /etc/sysctl.d/99-forgebox.conf <<'SYSCTL'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
net.ipv4.conf.all.src_valid_mark = 1
SYSCTL
sysctl --system >/dev/null

# --- 5. Firewall hint -------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  log "UFW is active. ForgeBox needs ports opened for the services you deploy."
  log "See docs/services.md for the full port table, then e.g.:"
  log "  ufw allow 8080/tcp  # Heimdall dashboard"
fi

ok "Done."
echo
ok "Next steps:"
echo "  1) cd /opt/forgebox   (copy docker-compose.yml + .env here, or clone the repo)"
echo "  2) cp .env.example .env && \$EDITOR .env"
echo "  3) docker compose up -d"
echo
