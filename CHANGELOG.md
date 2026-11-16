# Changelog

All notable changes to ForgeBox are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed (docs)
- **Removed a claim about npm's health status that was never established.** The
  healthchecks doc said npm "flips to healthy once nginx answers on :81". A
  bench run at the previous `start_period: 360s` reached `FailingStreak: 18`
  against a 30s interval, roughly nine minutes, still `unhealthy`. Whether that
  was init still running or init finished with `:81` still refusing was not
  determined, and those two are very different defects. `starting` now means
  "we do not know yet", with the chown check documented as the way to tell the
  two apart.



### Changed
- **npm is out of the `--wait` gate, on purpose, as branch (b).** Its first boot
  runs an s6 `prepare` oneshot (`chown -R` over the certbot site-packages tree,
  ~92 MB / 9.3k files) whose duration is not bounded by anything the project
  controls; measured still running **624s** after start on a clean bench. A
  `start_period` is a guess about a duration, and there is no duration here to
  guess, so `360s` was wrong and `900s` would be the same mistake with a bigger
  number. npm no longer gates the quick start: `smoke.sh` brings the stack up
  detached, then waits on every other service by name. npm's healthcheck is
  unchanged and still real, so `docker compose ps` shows `starting` for exactly
  as long as init takes. `start_period` for npm drops to 30s because it is no
  longer load-bearing.



### Fixed
- **Port check sees what `docker compose config` actually renders.** Section 3
  extracted published ports with a matcher that only understood short list
  syntax (`- "8080:80"`). Compose normalises every published port to long
  syntax (`- mode: ingress` / `target:` / `published:` / `protocol:`), so on a
  real render the parser found nothing, printed nothing, and exited 0. The
  check was passing on zero. It now parses all three shapes the file can take
  (short list, short inline, long syntax) and resolves the transport from
  `protocol:` so tcp/udp pairs stay distinct. Two long-syntax fixtures were
  added to the self-test, including a tcp/udp pair, because the old self-test
  only ever fed it short syntax and therefore could not catch this.

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

### Fixed
- **`start_period` is now 360s, up from 180s, and this one bit a real installer.**
  Measured on a clean Debian 13 host (Nov 2026): `heimdall` and `npm` each
  needed **270s** to pass their first health check. Deployed by hand, Docker
  tolerated it and both went healthy at ~271s. Deployed with
  `docker compose up --wait --wait-timeout`, it did not: the command gave up and
  printed `container forgebox-heimdall-1 is unhealthy` on an install that
  finished fully healthy a minute later. A first-time installer reads that line
  as a broken install. 360s is the 270s observation plus a third of headroom.
  `SMOKE_TIMEOUT` moved to match. Root cause inside `npm` is upstream, not ours:
  an s6 `prepare` oneshot runs `chown -R` over the certbot package tree and
  blocks `nginx` and `backend` until it returns.
