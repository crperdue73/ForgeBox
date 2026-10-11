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

### Known overlap

**Heimdall HTTPS (8443)** and **code-server (8443)** use the same number. If you run
both, edit one. Most people don't need Heimdall's built-in HTTPS — Nginx Proxy Manager
handles TLS for the whole lab.

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
