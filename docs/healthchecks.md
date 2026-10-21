# Healthchecks — why the probes look the way they do

**Policy: a healthcheck that cannot fail is not a healthcheck.**
Every probe here has been observed failing on a real host before it was
observed passing. If you add one, break it on purpose once and watch it go red.

## Probe style

Services that are still up declare this in `docker-compose.yml`:

```yaml
healthcheck:
  test: ["CMD-SHELL", "timeout 3 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/<port>' || exit 1"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 180s
```

We probe over loopback from *inside* the container, so the check survives a
changed `COMPOSE_PROJECT_NAME` and does not depend on any host port being free.

## Three exceptions, each verified on the LXC 2026-10-21

### portainer — no shell at all
The image is distroless: `/bin/sh` does not exist, so every `CMD-SHELL` probe
fails with `exec: "/bin/sh": no such file or directory` regardless of what is
listening. Observed failing live before the fix. Probe the binary instead:

```yaml
test: ["CMD", "/portainer", "--version"]
```

### glances — do not use `pid: host`
With `pid: host`, glances 4.5.8 crashes on boot in
`GlancesAutoDiscoverClient` with
`TypeError: gethostbyname() argument 1 must be str, bytes or bytearray, not None`
— its own hostname does not resolve in the host PID namespace. Confirmed by
A/B on the same host: with `pid: host` the container restart-looped
(RestartCount 10); without it, a 20s idle probe showed 0 crashes and the
healthcheck went healthy. Glances still sees every container through the
mounted `docker.sock`, so host PID visibility is not needed.

### The four exempt services
- `watchtower` — runs an ephemeral loop, no long-lived listener to probe.
- `homeassistant` — `network_mode: host`; loopback probing is meaningless here.
- `paperless_redis` — the image ships no shell and no client worth probing with.
- `paperless_db` — same; the app container's own readiness covers it.

## start_period is 180s on purpose

Linuxserver images generate TLS keys and finish a one-time install on first
boot. A 60s `start_period` marked them unhealthy mid-install, which is a lie
about a container doing exactly what it should. 180s is the observed ceiling
for the slowest of them. On a slow or contended host even 180s can be tight —
if a first boot reports unhealthy, check `docker logs` before assuming a bug.

## Known host constraint (not a compose bug)

Verified 2026-10-21: running a second full stack beside the live one on the
4GB LXC pushed the host to 47% iowait and load 19.9, and linuxserver init
scripts (`mv` during first-boot install) hung in uninterruptible D-state.
Their healthchecks then failed for lack of resources, not because of config.
Test one profile at a time on this box, or give the LXC more RAM.
