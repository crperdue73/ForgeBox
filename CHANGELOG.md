# Changelog

All notable changes to ForgeBox are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-11-15

First tagged release. Cut from `main` at commit `2af2f43` (2026-11-02) with no
functional changes: the tag exists so deployment testing has something fixed to
test against.

### What ForgeBox 1.0.0 is

One `docker-compose.yml` that stands up 31 services across 6 optional profiles
plus core. Profiles let a 4 GB mini-PC run the core and a bigger box run all of it:

| Profile | Services |
|---|---|
| *(core, no profile)* | Portainer, Heimdall, Nginx Proxy Manager, Uptime Kuma, Watchtower, Glances |
| `security` | Pi-hole, WireGuard, Vaultwarden |
| `vpn` | Gluetun *(opt-in, needs host `/dev/net/tun`)* |
| `devops` | Gitea, Semaphore, Jenkins, code-server, Guacamole |
| `media` | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Overseerr |
| `productivity` | Home Assistant, Paperless-ngx, Vikunja, Linkding, n8n |
| `files` | Nextcloud, Syncthing, Chibisafe |

### Changes since first public push (2026-10-15)

- **Portainer pinned to `2.45.3`** — matches the data volume already on the build
  box instead of predicting a newer one.
- **Nginx Proxy Manager unpinned to `latest`** — `2.16.0` came off the tag: the
  container boots, the `:81` healthcheck goes green, and the admin init path never
  completes. A healthcheck-green proxy that answers nothing. Known issue, tracked
  in the repo issues rather than carried as a pending task.
- **Glances pinned to `4.5.8-full`**, Gluetun to `v3.41.3`, WireGuard to
  `1.0.20260223`, Prowlarr to `2.6.5`, qBittorrent to `5.3.0`, Syncthing to `2.1.6`.
- **Docs**: troubleshooting notes for LXC hosts (no `/dev/net/tun`, so no Gluetun),
  healthcheck reference, service + port catalog, ADR log in `docs/decisions.md`.
- **`tests/smoke.sh`** — boots the stack and checks that every declared service
  reaches running state with its healthcheck passing.

### Known limitations at release

- `--profile "*"` includes `vpn`; on a host without `/dev/net/tun` that run brings
  up everything else and errors on Gluetun alone.
- Nginx Proxy Manager's `latest` roll is described above; if a future tag breaks
  init again, pin the last known-good digest.
- Verified on the Debian 12 / Docker Compose v2 build box. Not yet tested on
  DragonForge Linux itself, on ARM, or on Podman.
- No automated CI. `tests/smoke.sh` is run by hand.

### Verification honesty

The compose file was validated against a live Docker daemon on the build host.
`tests/smoke.sh` cannot run on a host without the Compose v2 plugin, and no claim
here was made from such a host.

[1.0.0]: https://github.com/crperdue73/ForgeBox/releases/tag/v1.0.0

## [Unreleased]

### Fixed (found by deployment testing, 2026-11-15)

- **`tests/smoke.sh` expected `watchtower` in core.** It is defined only under the
  `autoupdate` profile, deliberately, so a core-only run correctly refused to
  create it and the test called that a missing service. Watchtower is now
  expected only when its profile is selected.
- **`tests/smoke.sh` had a blanket no-`:latest` rule** that contradicted the
  documented Nginx Proxy Manager pin. The deliberate exemption is now listed
  explicitly and printed when it applies, so an accidental new `:latest` still
  fails while the argued-for one does not.
- **`tests/smoke.sh` failed on a fresh clone with no `.env`** (`PIHOLE_PASSWORD is
  missing a value`) at the exact moment a stranger is most likely to run it. It
  now parses against `.env.example` when no `.env` exists, says so in the PASS
  line, and never writes a `.env` of its own.

No change to `docker-compose.yml`. Product behaviour at `v1.0.0` is unchanged.

- **Check 3 (duplicate host ports) could pass on nothing.** It reported
  `no duplicate host ports (0 distinct)` and called that a pass. Zero published
  ports on this stack is impossible: a real `docker compose config` render shows
  37 distinct ports. A zero now fails the check and says why. The count is printed
  next to the verdict on every run. Also fixed: under `set -e` the check could kill
  the whole run mid-way with no verdict and no output when the port scan returned
  non-zero.
- **The result line now prints four counters** (`executed`, `passed`, `failed`,
  `skipped`). Publishing only the two that moved let 8 and 9 look like the same
  number.

- **Check 3 now names its units.** It printed one bare count, so two correct
  reporters publishing 37 and 35 looked like a disagreement: one was counting
  published entries, the other distinct port numbers. It now reads
  `37 published entries across 37 distinct host port numbers` (full profile: 37
  and 35, because pihole 53 and syncthing 22000 are each stated for tcp and udp).
