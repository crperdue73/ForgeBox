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

npm does not belong in the table above, and `start_period` was the wrong tool for
it. This section is the corrected account; the number is measured, the command
that produced it is given, and the earlier guesses are recorded so they do not
get repeated.

### The observation

From a **fresh volume**, full core stack, on a clean Debian 13 host (Nov 2026),
sampled while live:

- `chown -R 1000:1000 /opt/certbot/lib/python3.13/site-packages`, run by the
  image's s6 `prepare` oneshot on first boot.
- That tree is **92,307 KB / 9,303 files**.
- The chown was still running when sampling stopped at **624s**, at **15+
  minutes**, and at **17+ minutes**. `write_bytes` advanced at an unstable rate:
  17 MB in 46s, then 8 MB in 103s, then 8 MB in 130s. PID in state `D`, i.e.
  disk wait, not hung.
- `:81` refused from inside the container throughout.
- `FailingStreak` observed climbing through 4, 9, 20, 22, 23, 25.

**There is no witnessed completion time.** Every figure above is a lower bound
from a run still in progress. An earlier draft of this file quoted a completion
time of "19m32s (1172s)"; it has been removed because **nobody on this project
watched that run finish**, and a total with no witness is not a measurement. If a
future run completes under observation, that number belongs here with the
command that produced it and the note that it is one sample of an unstable rate,
not a ceiling.

### What a too-small `start_period` does

This is the part worth reading carefully, because the obvious guess is wrong.

Once `start_period` expires, `retries: 3` at `interval: 30s` marks the container
`unhealthy` within 90 seconds, and it **stays** red for the rest of init.

The container is **not broken**: `:81` refusing while the oneshot holds is the
expected consequence of init still running, it needs no intervention, and Docker
reports healthy again once nginx answers, with no restart. So the red flag is a
**lie about a working install that has not finished initialising**. That is the
defect: not a crash, not a hang, a display that tells a first-time installer their
install failed when it did not.

### First boot only

- `docker compose restart npm` (volume kept): no chown runs and it is healthy
  quickly.
- `docker compose down -v && docker compose up -d npm` (fresh volume): the chown
  runs again, unbounded.

This is why the problem is invisible on a machine where the stack has been
deployed before: the volume is already populated, the chown is skipped, and any
`start_period` looks generous. **Every honest install test starts from a fresh
volume, because that is what a stranger gets.**

### What ForgeBox does instead

Branch **(c)**: npm is out of the `--wait` gate, and its first-boot chown is
documented as upstream.

- npm declares no meaningful window (`start_period: 30s`); the number is not
  load-bearing and is not presented as a ceiling.
- `docker compose up --wait` does not gate on npm. `up --wait` has no per-service
  exclusion, so `tests/smoke.sh` starts the stack detached, then runs a second
  `up --wait` naming every service **except** npm.
- npm's healthcheck is unchanged and still real, so `docker compose ps` shows
  `starting` for exactly as long as init takes.
- Checklist for anyone who sees npm red on a first boot: `docker top <container>
  | grep chown`. **Chown present = init, wait. Chown gone and `:81` still
  refusing = a real defect, report it.**

Branch **(a)**, pinning `start_period` above the longest observed run, was
considered and rejected
for npm: it is still a number guessed about an unbounded operation, and a slower
disk or a larger tree beats it. Picking a bigger number each time someone reports
this is how a project ends up at 180 -> 360 -> 1800 and still failing.

Branch **(b)**, having the image signal readiness from its s6 oneshot, is the
real fix and it belongs upstream. It is out of scope for this project and is
tracked here rather than quietly forgotten.

## Known host constraint (not a compose bug)

Verified 2026-10-21: running a second full stack beside the live one on the
4GB LXC pushed the host to 47% iowait and load 19.9, and linuxserver init
scripts (`mv` during first-boot install) hung in uninterruptible D-state.
Their healthchecks then failed for lack of resources, not because of config.
Test one profile at a time on this box, or give the LXC more RAM.
