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

Full core stack, on a clean Debian 13 host (Nov 2026), sampled live. The first
observations came from a fresh volume; see the frequency section for why that
distinction turned out not to be load-bearing:

- `chown -R 1000:1000 /opt/certbot/lib/python3.13/site-packages`, run by the
  image's s6 `prepare` oneshot (frequency not established, see below).
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

### How often does it run? Not established.

An earlier draft of this file said **"first boot only,"** resting on a
`docker compose restart npm` that came back healthy quickly with no chown. That
story is now **withdrawn as unproven**, because a later observation contradicts
it:

- A container created at `02:56:58Z` (`created` 02:56:58.417, `started`
  02:56:58.753, `health=starting`, `fails=0`, `restarts=0`) had chown PID 15279
  running and `:81` **refusing** at 2m19s elapsed.
- Both of its mounts, `forgebox_npm_data` and `forgebox_npm_letsencrypt`, are
  **persistent Docker named volumes that were not recreated.** So this run was
  walking a tree a previous run had already walked, and was slow anyway.

If the cost were purely first-touch of the volume, reusing an already-chowned
volume would be fast. It was not. That points at **per-container-start** cost
rather than per-volume first touch, i.e. the s6 oneshot runs `chown -R` on every
start regardless of whether the data is already owned.

**That is not asserted as fact here.** It is one observation of one container
with no finished run, and the two explanations have not been separated by an
experiment. What follows from it is narrower and does not depend on which is
true:

- The docs must not claim "first boot only." It is not established.
- A stranger's *second* start may be just as slow as the first. Anyone planning
  restarts should sample `docker top <container> | grep chown` rather than
  assume a quick one.
- The distinguishing experiment, when someone has an idle box: `docker compose
  restart npm` with the volume untouched, and watch whether chown appears. If it
  does, the cost is per start. If it never does, something about volume state
  matters and the original story may hold.

Either way branch **(c)** is unaffected: if the walk can happen on any start,
then no `start_period` can be correct, and the argument is stronger rather than
weaker.

### What ForgeBox does instead

Branch **(c)**: npm is out of the `--wait` gate, and the chown is documented as
upstream.

- npm declares no meaningful window (`start_period: 30s`); the number is not
  load-bearing and is not presented as a ceiling.
- `docker compose up --wait` does not gate on npm. `up --wait` has no per-service
  exclusion, so `tests/smoke.sh` starts the stack detached, then runs a second
  `up --wait` naming every service **except** npm.
- npm's healthcheck is unchanged and still real, so `docker compose ps` shows
  `starting` for exactly as long as init takes.
- Checklist for anyone who sees npm red at any start: `docker top <container>
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
