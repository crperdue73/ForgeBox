# Decisions

Why the file is shaped the way it is. Read this before changing anything that
looks odd — most of it is odd on purpose, and every oddity has a failure behind it.

## Ports are the container's real ports, not the ones you wish it had

`code-server` is published on host `8444` → container `8443` because that is where
the linuxserver image listens. `nextcloud` is published on `8030` → container `80`
for the same reason: lsio's Nextcloud runs nginx on 80 and there is no 443
listener at all. An incorrect mapping is invisible to every liveness check — the
container is healthy, `docker port` reports the mapping, and the browser gets a
connection reset.

If you change a port, verify it with an actual request to the published host port,
not with `docker ps`.

## TLS lives in front, not in each service

`nginx-proxy-manager` owns 80/443 in the core profile. Individual services stay
plain HTTP behind it. Do not add TLS to a service unless it is the proxy.

## PGDATA is set explicitly

`paperless_db` sets `PGDATA: /var/lib/postgresql/data/pgdata` and mounts the volume
at the parent directory. The postgres 18 line moved the default data directory, so
a container mounting the old path after a tag bump would initialize a *fresh empty*
cluster, report healthy, and serve an empty Paperless while the real data sat
untouched on the volume. Postgres refusing to start is the safe failure; succeeding
wrongly is the dangerous one.

## Semaphore is pinned, and here is why

`semaphoreui/semaphore:v2.18.10`. Newer releases on the 2.18 line and above were
pro builds that panicked on BoltDB. Do not move this pin without testing the target
version on a scratch box first.

## vikunja runs as root

Its image ships `/app/vikunja/files` owned by root while the process runs as uid
1000, which breaks under rootless/user-namespace Docker.

## gluetun is in its own profile

It needs `/dev/net/tun`. On an LXC host without TUN mapped in, it fails — and it
fails the whole profile it sits in. Isolating it keeps `--profile "*"` working on
hosts that cannot do VPN passthrough.

## chibisafe listens on 8001

Not 8000. That is what the image does.

## Auto-update is opt-in, and off in classrooms

`watchtower` lives behind `--profile autoupdate`, never in core. Every pin in this
file is undone within one poll interval otherwise, and the failures it causes are
one-way: Nextcloud app versions cannot be downgraded, n8n migrates its SQLite
schema with no rollback, and Postgres may not see a data directory from a newer
major at all.

A student should be able to answer *what version am I on* without a machine that
changes the answer while they sleep.

## No `container_name`, no fixed network name

Compose scopes names to the project directory. With `container_name` set, a host
supported exactly one ForgeBox — a second `up` collided on container names and on
the network. Removing both is what makes two students, or two lessons, able to run
side by side.
