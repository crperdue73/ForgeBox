# ForgeBox — the container catalog

ForgeBox ships 30+ services, grouped by purpose. Core services always deploy;
everything else is behind a **compose profile** so you can run exactly what your
hardware can carry.

## Port map (no conflicts — guaranteed)

| Service | Profile | Host port(s) | Purpose |
|---|---|---|---|
| **Portainer** | core | 9000 | Docker management UI |
| **Heimdall** | core | 8080, 8443 | Dashboard / launchpad |
| **Nginx Proxy Manager** | core | 80, 443, 81 | Reverse proxy + SSL |
| **Uptime Kuma** | core | 3001 | Service monitoring + alerts |
| **Watchtower** | core | — | Automated container updates |
| **Glances** | core | 61208 | Real-time system monitoring |
| Pi-hole | security | 53, 8010 | Network DNS + ad blocking |
| WireGuard | security | 51820/udp | VPN server |
| Vaultwarden | security | 8020 | Password manager |
| Gluetun | security | 8888 | VPN client gateway |
| Gitea | devops | 3000, 2222 | Self-hosted Git |
| Semaphore | devops | 3010 | Ansible control UI |
| Jenkins | devops | 8081, 50000 | CI engine |
| code-server | devops | 8444 | VS Code in the browser |
| Guacamole | devops | 8082 | Clientless remote desktop |
| Jellyfin | media | 8096 | Media server |
| Sonarr | media | 8989 | TV automation |
| Radarr | media | 7878 | Movie automation |
| Prowlarr | media | 9696 | Indexer manager |
| qBittorrent | media | 8085 | Torrent client |
| Overseerr | media | 5055 | Media request portal |
| Home Assistant | productivity | host | Smart home |
| Paperless-ngx | productivity | 8011 | Document archive |
| Vikunja | productivity | 3456 | Tasks / projects |
| Linkding | productivity | 9090 | Bookmarks |
| n8n | productivity | 5678 | Workflow automation |
| Nextcloud | files | 8030 | Private cloud suite |
| Syncthing | files | 8384, 22000, 21027 | Decentralized sync |
| Chibisafe | files | 8040 | File drop / sharing |

> Note: **code-server** upstream defaults to 8443, the same number **Heimdall** uses
> for its HTTPS port. ForgeBox maps code-server to host **8444** so both can run at
> once (see the Troubleshooting doc). Heimdall keeps 8443.

## Sizing guidance

- **core** — ~1.5 GB RAM, small disk. Fine on a 2c/4G box.
- **+devops** — Jenkins is the hungry one (1–2 GB). Gitea/Semaphore are light.
- **+media** — Jellyfin transcodes on CPU; \*arr + qBittorrent add ~1 GB. Disk grows fast.
- **+productivity** — Home Assistant is light; Paperless pulls in Postgres + Redis.
- **+files** — Nextcloud + Syncthing are storage-bound, not CPU-bound.

## How profiles work

Profiles are additive. A service with `profiles: [devops]` starts only when you pass
`--profile devops`. Core services have `profiles: []` and always start.

```bash
docker compose --profile devops --profile media up -d
```
