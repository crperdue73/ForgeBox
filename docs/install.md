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

Every first-login below is the *upstream default*. Where ForgeBox pre-seeds a
credential from `.env` it says so — otherwise the service asks you to create the
admin on first visit.

> **Change every default password immediately.** `changeme` is a placeholder, not a policy.

### core (always deployed)

| Service | URL | First login |
|---|---|---|
| Heimdall | `http://host:8080` | No login — start here, the launchpad. Add app tiles yourself. |
| Portainer | `http://host:9000` | First visit: create the admin user (you set the password). |
| Nginx Proxy Manager | `http://host:81` | Default `admin@example.com` / `changeme` — change on first login. |
| Uptime Kuma | `http://host:3001` | First visit: create the admin user. |
| Glances | `http://host:61208` | No auth by default — read-only system monitor. |
| Watchtower | *(none)* | Headless. It just updates containers; check logs with `docker logs watchtower`. |

### devops (`--profile devops`)

| Service | URL | First login |
|---|---|---|
| Gitea | `http://host:3000` | Install wizard on first visit — pick SQLite, set the admin. |
| Semaphore | `http://host:3010` | `admin` / `$SEMAPHORE_ADMIN_PASSWORD` from `.env` (`admin@forgebox.local`). Changing it in the UI is fine. |
| Jenkins | `http://host:8081` | Unlock with the initial admin password: `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`, then install suggested plugins + create the admin. |
| code-server | `http://host:8444` | **No auth out of the box** (linuxserver default `auth: none`) — put it behind NPM or set a password. Mapped to 8444; 8443 is Heimdall's HTTPS port. |
| Guacamole | `http://host:8082` | Default `guacadmin` / `guacadmin` — **change immediately**, it's a remote-desktop gateway. |

### security (`--profile security`)

| Service | URL | First login |
|---|---|---|
| Pi-hole | `http://host:8010/admin` | Password is `$PIHOLE_PASSWORD` from `.env` (set it — the installer auto-generates one if left blank). |
| Vaultwarden | `http://host:8020` | No default account — "Create account" to make the first (admin) user. |
| WireGuard | *(none)* | Config-driven. Check `docker logs wireguard` for the generated peer QR/config. |
| Gluetun | *(none)* | Headless VPN client gateway. Needs `WIREGUARD_PRIVATE_KEY`; check `docker logs gluetun` for the connection state. |

### media (`--profile media`)

| Service | URL | First login |
|---|---|---|
| Jellyfin | `http://host:8096` | Setup wizard — create the admin on first visit. |
| Sonarr | `http://host:8989` | No auth by default on first visit — set a login in Settings → General → Authentication. |
| Radarr | `http://host:7878` | Same as Sonarr — set auth in Settings → General. |
| Prowlarr | `http://host:9696` | Same pattern — set auth in Settings → General. |
| qBittorrent | `http://host:8085` | Temporary password is printed in the logs: `docker logs qbittorrent`. Change it on first login. |
| Overseerr | `http://host:5055` | Sign in with Plex (or set up local admin), then link Jellyfin/Plex. |

### productivity (`--profile productivity`)

| Service | URL | First login |
|---|---|---|
| Home Assistant | `http://host:8123` | Onboarding wizard — create the owner account on first visit. |
| Paperless-ngx | `http://host:8011` | Default `admin` / `admin` — **change immediately**. DB password comes from `.env`. |
| Vikunja | `http://host:3456` | Register the first account (it becomes the admin). |
| Linkding | `http://host:9090` | Create the superuser on first visit. |
| n8n | `http://host:5678` | Owner setup on first visit — set email/password. Encryption key from `.env`. |

### files (`--profile files`)

| Service | URL | First login |
|---|---|---|
| Nextcloud | `http://host:8030` | Setup wizard — create the admin user. DB comes from the bundled Postgres. |
| Syncthing | `http://host:8384` | Web UI is open by default — set a GUI user/password in Settings immediately. |
| Chibisafe | `http://host:8040` | First-visit setup — create the admin. |
