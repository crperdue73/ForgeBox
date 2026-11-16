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
(Nov 2026) `heimdall` needed **270s** to pass its first health check, against a
declared 180s window. Two consequences, and the second is the one that mattered:

1. Docker tolerated it. When a health check fails inside `start_period`, the
   container is not marked unhealthy, it just starts its retries again, so it
   went healthy at ~271s anyway.
2. `docker compose up --wait --wait-timeout` did not tolerate it. That command
   gave up and printed `container forgebox-heimdall-1 is unhealthy` on an
   install that finished fully healthy a minute later. A first-time installer
   reads that line as a failed install.

360s is now the declared window for services that boot on a clock: the observed
270s ceiling plus a third of headroom for a slower host. If a first boot still
reports unhealthy after 360s, that is worth a `docker logs` look rather than an
assumption.

## npm is not on a clock, and is not gated

npm does not belong in that table, and 360s was wrong for it. Corrected on a
clean bench (2026-11-16), with the number and the command that produced it:

- npm `StartedAt` `02:34:04Z`; at `02:44:28Z` it was still `unhealthy`,
  `FailingStreak=9`, and **624s into its first boot**.
- `docker top forgebox-npm-1 | grep -c "chown -R"` -> `1` (still running).
- The process: `chown -R 1000:1000 /opt/certbot/lib/python3.13/site-packages`.
- `du -s` on that tree: two independent samples, `92,307 KB / 9,303 files` and
  `91 MB / 8,197 files`. Same order, different counters (different measurement,
  same tree). The point is the size, not the exact digit.

So it is not a slow boot with a duration, it is a **filesystem walk with no
fixed duration**. That is the whole distinction. 270s was one sample of an
unbounded operation, and presenting it as a ceiling was a mistake worth writing
down. You cannot pick a `start_period` that covers work whose length you do not
control; 900s would be the same guess with a bigger number, and it would still
lose on a slow disk or a bigger tree.

**What ForgeBox does instead (decided 2026-11-16):**

- npm declares no meaningful window (`start_period: 30s`); its healthcheck
  stays real and keeps running.
- `docker compose up --wait` does not gate on npm. `up --wait` has no
  per-service exclusion, so `tests/smoke.sh` starts the stack detached, then
  runs a second `up --wait` naming every service **except** npm.
- `docker compose ps` will show npm as `starting` for however long init actually
  takes.
- Second and later boots skip the chown and are quick.

**What the health status does NOT promise, and this is a correction.** An
earlier draft of this file said npm "flips to healthy once nginx answers on
:81." That is not something this project can promise, and a bench observation
proves it:

- npm ran with `start_period: 360s` (the previous value) and reached
  `FailingStreak: 18` against `interval: 30s`, i.e. roughly nine minutes of
  failing probes, with the container still `health=unhealthy`.
- Whether that was (i) init still chowning, so nginx was genuinely not up yet,
  or (ii) init finished and nginx still not answering on `:81`, **was not
  established.** Option (ii) would be the same class of fault as the 2.16.0
  proxy-up-with-no-admin-behind-it regression.

The distinction matters and the project does not get to assume the flattering
one. So:

- A `start_period` does not merely risk being too short. `FailingStreak`
  counts probes after the window ends, so a container can sit at
  `unhealthy` indefinitely while its init is still legitimately running. That
  is the strongest argument for not putting the gate on a clock at all.
- `starting` is not a promise that the next state is `healthy`. It means "we do
  not know yet", which is the truth.
- Anyone seeing npm `unhealthy` on a first boot should check
  `docker top <container> | grep chown` before concluding the container is
  broken. If chown is still running, it is init. If chown is gone and `:81`
  still refuses, that is a real defect and should be reported as one.

**The honest limit, stated rather than hidden:** a stranger's very first
`up --wait`, run by hand and not through `smoke.sh`, can still print npm as
unhealthy on a first boot, because flags on the CLI, not just in the file,
decide that. The remedy is upstream (npm's s6 `prepare` oneshot should signal
readiness instead of the healthcheck guessing on a clock), and this project's
part is to stop guessing.

## Known host constraint (not a compose bug)

Verified 2026-10-21: running a second full stack beside the live one on the
4GB LXC pushed the host to 47% iowait and load 19.9, and linuxserver init
scripts (`mv` during first-boot install) hung in uninterruptible D-state.
Their healthchecks then failed for lack of resources, not because of config.
Test one profile at a time on this box, or give the LXC more RAM.
