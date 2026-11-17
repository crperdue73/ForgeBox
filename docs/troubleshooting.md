# Troubleshooting ForgeBox

## A container won't start

```bash
docker compose ps                 # see status
docker compose logs <service>     # read the why
docker compose logs -f <service>  # follow
```

Nine times out of ten the log names a port already in use or a missing env var.

## "port is already allocated"

Something else on the host owns that port. Check what:

```bash
sudo ss -tulpn | grep <port>
```

Then either stop the other thing, or change ForgeBox's mapping in
`docker-compose.yml` (and note it). The `docs/services.md` port map is designed to be
conflict-free **within** ForgeBox; the host may still have its own listener.

### Known overlap (resolved)

**Heimdall HTTPS (8443)** and **code-server** both default to 8443. ForgeBox maps
code-server to host **8444** (`8444:8443`) so both run at once. If you'd rather keep
code-server on 8443, drop Heimdall's `8443:443` mapping — most people don't need
Hemidall's built-in HTTPS since Nginx Proxy Manager handles TLS for the whole lab.

## `apt-get update` fails on the DragonForge repo

Symptom:

```
OpenPGP signature verification failed ... Missing key ...
```

The DragonForge apt repository's published signing key may be out of date or invalid.
Temporarily disable that one repo so it stops blocking updates:

```bash
sudo sed -i 's/^deb /#deb /' /etc/apt/sources.list.d/dragonforgelinux.list
sudo apt-get update
```

Then report it — the repo operator needs to republish a valid keyring. (ForgeBox's own
dependencies come from Debian + Docker's repos, so this does not block ForgeBox.)

## `Could not get lock /var/lib/dpkg/lock-frontend`

Another package process (often `unattended-upgrades`) is running. Wait for it:

```bash
ps aux | grep -E "apt|dpkg|unattended"
```

Then retry. During automated provisioning you can pause the auto-updater:

```bash
sudo systemctl mask --now unattended-upgrades
```

## Container starts then exits immediately

Usually a permissions or a missing-secret issue.

- Check `PUID`/`PGID` in `.env` match the owner of your data directories.
- Check required env vars (a service with `:?` in the compose file **requires** the var).

## code-server is password-gated by ForgeBox (upstream default: no auth)

`lscr.io/linuxserver/code-server` ships with `auth: none` — a browser VS Code with
shell access to the host, reachable by anyone who can hit port **8444**. On a trusted
LAN that's survivable; for a "datacenter-in-a-box" it isn't good enough.

**ForgeBox closes this by default.** The `code-server` service in `docker-compose.yml`
sets `PASSWORD: ${CODE_SERVER_PASSWORD:-change-me}`, and `install.sh` auto-generates a
random `CODE_SERVER_PASSWORD` in `.env` (chmod 600) when the value is left at
`change-me`. So a fresh ForgeBox deploy prompts for a password at `http://host:8444`
instead of handing out an anonymous shell.

To set your own:

1. Put `CODE_SERVER_PASSWORD=something-strong` in `.env` before deploying (or edit and
   `docker compose up -d code-server` to recreate). The install answer file
   (`install.sh --answers FILE`) accepts the same key.
2. Prefer **no plaintext in the environment**? Use `HASHED_PASSWORD` instead —
   generate one with `echo -n 'yourpass' | argon2 "$(openssl rand -base64 16)" -id -t 3 -m 16 -p 4`
   and replace the `PASSWORD:` line with `HASHED_PASSWORD: ${CODE_SERVER_HASHED_PASSWORD}`.

Defense in depth: you can also put it behind the reverse proxy (Nginx Proxy Manager)
and/or fire a UFW rule so 8444 is only reachable from your admin subnet.

> On versions predating the built-in password, 8444 was open to anyone who could
> reach the host. Do **not** expose 8444 to an untrusted network without a password.

## Gluetun won't start: `/dev/net/tun: no such file or directory`

Symptom — `docker compose --profile security up -d` leaves `gluetun` stuck in
`created` (exit 128) with:

```
error gathering device information while adding custom device "/dev/net/tun": no such file or directory
```

ForgeBox's `gluetun` service (the VPN gateway) declares `devices: [/dev/net/tun:/dev/net/tun]`.
On bare metal that node always exists. In an **unprivileged LXC/incus container** the host
must pass it through — the kernel has tun support, but the container has no `/dev/net/tun`
device node, so the container never starts.

**Gluetun is opt-in by design.** It lives in its own `vpn` profile, *not* in
`security`, so a plain `up -d`, `--profile security`, or `--profile "*"` never tries
to start it — and never errors on a host without `/dev/net/tun`. You only ever hit
the symptom below if you ask for it explicitly:

```bash
docker compose --profile vpn up -d
```

Fix (run on the **LXC host**, not inside the container), replace `VMID` with the
container's id, then restart the container:

```bash
# Proxmox / lxc
lxc.cgroup2.devices.allow: c 10:200 rwm    # add to /etc/pve/lxc/VMID.conf
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

Or run ForgeBox inside a **privileged** LXC / a VM / bare metal. `wireguard` (also in the
`security` profile) runs without the node but still needs a valid peer config to build a
tunnel. Gluetun is not required for the rest of the stack — just don't pass
`--profile vpn` on a host that lacks the device, and everything else runs fine.

## npm takes ~20 minutes and looks broken

Symptom — on a **new** `npm` container, `docker compose ps` shows `npm` as `starting` for the
first ~90 seconds and `unhealthy` for the rest of init, and `:81` refuses connections. The
rest of the stack is up.

**This is init, not a failure.** The image runs an s6 `prepare` oneshot on container
start: `chown -R` over the certbot site-packages tree (92,307 KB / 9,303 files). It is an
unbounded filesystem walk — observed at 624s, 15+ minutes, 17+ minutes, >1234s (~20.5 min)
and >1317s (~22 min) across clean-room benches, the last measured end to end. Faster
disks finish sooner; there is no number that is correct for every host.

**Why it goes red instead of staying amber:** `start_period` is 30s and `retries: 3` at
`interval: 30s`, so Docker calls it `unhealthy` about 90 seconds in and keeps saying so
until init finishes. That status is honest about `:81` and is not a verdict on your
install. Do not try to fix it by raising `start_period` — see
`docs/healthchecks.md` for why that is a guess that a slower host will always beat.

**Which events pay it:**

- first start of any **new** container — yes, whatever the state of the volumes;
- `docker restart npm` — **no**, seconds, healthy in ~20s;
- `docker compose up --force-recreate`, an image re-pull, or a rebuild — **yes, again**,
  even on warm volumes you have run for weeks.

That `/opt/certbot` is not a mounted volume is the whole reason: only `/data` and
`/etc/letsencrypt` are. It lives in the container's writable layer, so a new container
gets a fresh copy to walk and a restart of the same container does not.

To tell init from a real defect, ask the namespace:

```bash
docker top forgebox-npm-1 | grep chown
```

`chown` present = still initialising, wait. `chown` gone and `:81` still refusing =
something is actually wrong, open an issue with `docker compose logs npm`.

If `tests/smoke.sh --up` reports npm as **SKIP** rather than PASS or FAIL, it means exactly
that indeterminate state: `unhealthy` with no chown visible. It is not a pass, and it is
not the suite guessing a failure — check the log line it prints.

Do **not** run plain `docker compose up --wait` as your first command. It gates on every
healthcheck or none, with no per-service opt-out, so it exits 1 on npm and prints
`unhealthy` about an install that is working. Use `install.sh`, `tests/smoke.sh --up`, or
`docker compose up -d` then wait on your own. See `docs/healthchecks.md`.

## Out of disk

The media and files profiles grow without bound.

```bash
docker system df          # where space went
docker system prune -a    # remove unused images/containers (careful)
```

Move `MEDIA_PATH` to a bigger disk by editing `.env`.

## Still stuck?

Open an issue on the repo with: `docker compose ps`, the failing service's logs, and
your host's `free -h` + `df -h` output.
