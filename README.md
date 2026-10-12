# ForgeBox

**Your enterprise homelab, unleashed.**
Turn that unused PC into a powerful, professional-grade datacenter with a single command.

> That unused PC in the corner? It's a datacenter. You just haven't run the command yet.

## What is ForgeBox?

ForgeBox is a complete **"Datacenter-in-a-Box"** solution that transforms any standard
computer — an old desktop, a retired workstation, or a mini-PC — into a fully-featured
homelab. It ships as a pre-configured, integrated stack of the same enterprise-grade
tools used by IT professionals worldwide, managed through one unified system.

The magic is a single `docker-compose.yml`. After a minimal setup, you run one command.
ForgeBox deploys and connects 30+ essential services — tested **together**, so there are
no port conflicts, dependency issues, or version mismatches to fight at 2 AM.

## What makes it different

- **Tested together, not just collected.** Every container is pre-configured to coexist.
- **Built for DragonForge Linux.** The Gitea + Semaphore + Jenkins trio mirrors real
  DevOps workflows you'll be tested on.
- **One command to deploy, zero commands to maintain.** Watchtower updates; Uptime Kuma watches.
- **Total control.** Your data, your rules. No subscriptions.

## Quick start

```bash
# 1. Install Docker + git on a fresh Debian/Ubuntu host
bash install.sh

# 2. Configure
cp .env.example .env && $EDITOR .env

# 3. Deploy the core
docker compose up -d
```

Then open the ForgeBox dashboard (Heimdall) at `http://<host>:8080`.

### Add more of the stack (profiles)

ForgeBox uses **compose profiles** so a small host can run a subset and a big one can run it all.

```bash
docker compose up -d                                   # core only
docker compose --profile devops up -d                  # core + DevOps
docker compose --profile devops --profile media up -d  # several
docker compose --profile "*" up -d                     # everything
```

> **Note:** there is no profile literally named `all`. Use the wildcard
> `--profile "*"` (keep the quotes so your shell doesn't glob it) to enable
> every profile — `--profile all` silently starts core only.

| Profile        | Services |
|----------------|----------|
| *(core, none)* | Portainer, Heimdall, Nginx Proxy Manager, Uptime Kuma, Watchtower, Glances |
| `security`     | Pi-hole, WireGuard, Vaultwarden, Gluetun |
| `devops`       | Gitea, Semaphore, Jenkins, code-server, Guacamole |
| `media`        | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Overseerr |
| `productivity` | Home Assistant, Paperless-ngx, Vikunja, Linkding, n8n |
| `files`        | Nextcloud, Syncthing, Chibisafe |

## Documentation

- [`docs/install.md`](docs/install.md) — full install guide
- [`docs/quick-start.md`](docs/quick-start.md) — first-run walkthrough
- [`docs/services.md`](docs/services.md) — the container catalog + port table
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — when things go sideways

## Requirements

- A 64-bit host running Debian 12+ / Ubuntu 22.04+ (DragonForge Linux recommended)
- Docker Engine + Compose v2
- 2 cores / 4 GB RAM minimum for the **core** profile
- More for the heavy profiles (see `docs/services.md` for sizing)

## License

See [`LICENSE`](LICENSE).

---

_Maintained by **CR Perdue Technologies**. Built for the DragonForge Linux learning path._
