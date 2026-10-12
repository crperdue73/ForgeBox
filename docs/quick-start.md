# ForgeBox Quick Start

**Goal:** from a spare PC to a running dashboard in an afternoon.

## 1. Get the repo

```bash
git clone https://github.com/crperdue73/ForgeBox.git
cd ForgeBox
```

## 2. Install the host bits

```bash
sudo bash install.sh
```

This installs Docker, Compose v2, and git, and prepares `/opt/forgebox`.

## 3. Configure

```bash
cp .env.example .env
nano .env
```

Set your timezone and any passwords for the profiles you plan to use.

## 4. Start the core

```bash
docker compose up -d
docker compose ps
```

Give it a minute. Then open:

- **http://<host-ip>:8080** — Heimdall (your launchpad)
- **http://<host-ip>:9000** — Portainer (create your admin account here first)

## 5. Add more of the stack

```bash
docker compose --profile devops up -d      # Git, Ansible, CI
docker compose --profile media up -d       # Jellyfin + friends
```

Or bring up everything at once:

```bash
docker compose --profile "*" up -d
```

> There is no profile named `all` — use the wildcard `--profile "*"` (quotes
> required). `--profile all` matches nothing and starts core only.

## 6. Keep it healthy

- Watchtower (core) auto-updates containers daily — set and forget.
- Uptime Kuma (core) monitors your services and alerts you when one falls.
- Glances (core) shows live CPU/RAM/disk at `http://<host-ip>:61208`.

## Common first tasks

**Point Heimdall at everything.** Heimdall is a launchpad — add each service as a tile.
Use the host IP plus the port from `docs/services.md`.

**Put a real name on it.** Nginx Proxy Manager (port 81) lets you map `jellyfin.home`
→ Jellyfin and issue local SSL certs. See `docs/services.md`.

**Lock it down.** Enable the `security` profile for Pi-hole DNS, a WireGuard VPN, and
Vaultwarden — then you can reach your lab from anywhere without exposing ports.

## Where to go next

- `docs/install.md` — the full install guide
- `docs/services.md` — every service, every port, sizing
- `docs/troubleshooting.md` — when a container won't come up
