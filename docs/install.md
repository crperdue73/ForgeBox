# Installing ForgeBox

ForgeBox runs on any 64-bit Linux host with Docker. It is built for and tested on
**DragonForge Linux** (Debian-based), but works on Debian 12+ and Ubuntu 22.04+.

## Requirements

| | Minimum (core) | Recommended (full stack) |
|---|---|---|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8–16 GB |
| Disk | 20 GB | 100 GB+ (media libraries grow) |
| OS | Debian 12 / Ubuntu 22.04+ | DragonForge Linux |

> The **core** profile is happy on 4 GB. Media (Jellyfin + \*arr), Nextcloud, and
> Jenkins are the heavy ones — add RAM before enabling those.

## One-command install

On a fresh host:

```bash
git clone https://github.com/crperdue73/ForgeBox.git
cd ForgeBox
sudo bash install.sh
```

`install.sh` installs Docker Engine + the Compose v2 plugin + git, creates
`/opt/forgebox`, applies the kernel tweaks the media stack needs, and tells you the
next step. It does **not** start containers — that's yours to run.

### Unattended install / answer file

For provisioning scripts or hands-off bring-up, `install.sh` can seed `.env` and
deploy without prompts:

```bash
sudo bash install.sh --unattended           # seed .env, auto-generate secrets
sudo bash install.sh --answers my.env       # seed .env from an answers file
sudo bash install.sh --deploy               # ...then run `docker compose up -d`
sudo bash install.sh --answers my.env --deploy   # fully hands-off host
```

The **answers file** is plain `KEY=value` lines (same keys as `.env.example`);
`#` comments and blank lines are ignored. Precedence is
`existing .env` < `.env.example` < answers file. Any secret still left at
`change-me` (`PAPERLESS_DBPASS`, `PAPERLESS_SECRET_KEY`, `N8N_ENCRYPTION_KEY`,
`PIHOLE_PASSWORD`, `SEMAPHORE_ADMIN_PASSWORD`) is auto-generated, and `.env` is
written `chmod 600`. The seeding step is idempotent — a re-run never clobbers an
existing `.env` or regenerates a secret already set.

Example `answers.env`:

```ini
TZ=America/Chicago
PUID=1000
PGID=1000
SEMAPHORE_ADMIN_PASSWORD=a-real-password
WIREGUARD_PRIVATE_KEY=...
```

If `WIREGUARD_PRIVATE_KEY` is left empty the installer warns (not fails) — the
Gluetun/qBittorrent VPN path stays disabled until it's filled in.

## Configure

```bash
cp .env.example .env
$EDITOR .env
```

At minimum set a real password for Pi-hole (`PIHOLE_PASSWORD`) if you enable the
`security` profile, and the Semaphore admin password if you enable `devops`.

## Deploy

```bash
docker compose up -d                 # core
docker compose --profile devops up -d
docker compose --profile all up -d   # everything
```

Watch it come up:

```bash
docker compose ps
```

Then open the dashboard: `http://<host-ip>:8080` (Heimdall).

## Uninstall

```bash
docker compose --profile all down        # stop + remove containers
docker compose --profile all down -v     # ALSO delete volumes (data loss!)
```

## First-login cheat sheet

| Service | URL | Notes |
|---|---|---|
| Heimdall | `http://host:8080` | Start here — the launchpad |
| Portainer | `http://host:9000` | Create admin on first visit |
| Nginx Proxy Manager | `http://host:81` | Default login `admin@example.com` / `changeme` |
| Uptime Kuma | `http://host:3001` | Create admin on first visit |
| Gitea | `http://host:3000` | Install wizard on first visit |

> **Change every default password immediately.** `changeme` is a placeholder, not a policy.
