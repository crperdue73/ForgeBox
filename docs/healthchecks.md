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

## start_period is 360s on purpose

Linuxserver images generate TLS keys and finish a one-time install on first
boot. A 60s `start_period` marked them unhealthy mid-install, which is a lie
about a container doing exactly what it should.

The number came down from a measurement, not a guess. On a clean Debian 13 host
(Nov 2026) `heimdall` and `npm` both needed **270s** to pass their first
health check, against a declared 180s window. Two consequences, and the second
is the one that mattered:

1. Docker tolerated it. When a health check fails inside `start_period`, the
   container is not marked unhealthy, it just starts its retries again, so both
   containers went healthy at ~271s anyway.
2. `docker compose up --wait --wait-timeout` did not tolerate it. That command
   gave up and printed `container forgebox-heimdall-1 is unhealthy` on an
   install that finished fully healthy a minute later. A first-time installer
   reads that line as a failed install.

360s is now the declared window: the observed 270s ceiling plus a third of
headroom for a slower host. If a first boot still reports unhealthy after
360s, that is worth a `docker logs` look rather than an assumption.

## Known host constraint (not a compose bug)

Verified 2026-10-21: running a second full stack beside the live one on the
4GB LXC pushed the host to 47% iowait and load 19.9, and linuxserver init
scripts (`mv` during first-boot install) hung in uninterruptible D-state.
Their healthchecks then failed for lack of resources, not because of config.
Test one profile at a time on this box, or give the LXC more RAM.
