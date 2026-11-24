# Running Capsa behind Traefik

This folder runs Capsa (API and web app) as two containers behind an existing
[Traefik](https://traefik.io/) that discovers services by container labels. Tested with
rootless podman and `podman compose`; `docker compose` works the same way.

Nothing in the app is tied to a domain: the domain, Traefik's entrypoint and network,
the profile folder and the instance name are all set in `.env`.

## Requirements

- Traefik with the Docker provider (for podman: pointed at the podman socket) and an
  HTTPS entrypoint.
- A container network that Traefik uses to reach services (default name `traefik`).
- A TLS certificate for the domain in Traefik. The routers only set `tls=true`, which
  fits a wildcard certificate from Traefik's file provider. With an ACME certificate
  resolver, add the resolver label (see below).
- DNS for the domain. HTTPS is mandatory: browsers only run service workers (offline
  use) on secure origins. On a home network, split DNS pointing the name to the
  server's internal address is enough (SPEC 9).

## First start

```sh
cd deploy/production
cp .env.example .env              # set CAPSA_DOMAIN, check the Traefik names
mkdir -p profiles                 # or point CAPSA_PROFILE_DIR elsewhere
cp ../../profiles/demo/demo-latin.yaml profiles/   # and your own profiles
podman compose up -d --build
```

Traefik routes a container only once its health check passes (about 10 seconds after
start). Then create the first admin (parent) account and the learners:

```sh
podman exec -it capsa-api capsa user add papa --admin    # asks for the password
podman exec -it capsa-api capsa user add lena --display-name Lena   # optional
podman exec -it capsa-api capsa user grant lena demo-latin
```

With a different `CAPSA_INSTANCE`, the containers are called `<instance>-api` and
`<instance>-web`.

## In a separate service folder

`compose.yaml` does not have to stay in the repository. To keep the configuration with
other services (say, one folder per service in a versioned `/etc`-style repository),
copy `compose.yaml` and `.env.example` into that folder and point `CAPSA_SOURCE` at a
Capsa checkout on the server:

```sh
git clone https://git.example.org/capsa.git /srv/src/capsa
git -C /srv/src/capsa checkout v2026.11

mkdir capsa && cd capsa            # the service folder
cp /srv/src/capsa/deploy/production/compose.yaml .
cp /srv/src/capsa/deploy/production/.env.example .env
# .env: CAPSA_DOMAIN, CAPSA_VERSION=2026.11, CAPSA_SOURCE=/srv/src/capsa
mkdir profiles                     # see Profiles below
podman compose up -d
```

With `CAPSA_VERSION` set, a plain `podman compose up -d` builds the images when no
image with that tag exists yet, so start scripts that never pass `--build` keep working.
If that folder is versioned, keep profiles with book content out of it (ignore
`profiles/`, or set `CAPSA_PROFILE_DIR` to a folder outside).

## Profiles

The profile folder is mounted read-only. Copy a new or changed YAML file into it and
the server picks it up without a restart; invalid profiles are skipped and logged
(check with `podman logs capsa-api`). Validate before copying:
`uv run capsa lint my-profile.yaml`. Profiles with book content stay private: they are
only served to signed-in accounts they are released to.

## Updates

```sh
git pull
podman compose up -d --build
```

In a separate service folder: check out the new release tag in the `CAPSA_SOURCE`
checkout, set `CAPSA_VERSION` to it, then `podman compose up -d` (which builds the new
images, since that tag does not exist yet). Compare `compose.yaml` with the one in the
checkout (`diff`) in case a release changed it.

Database migrations run automatically when the API container starts. Learners get the
new app version offered in the app ("Neue Version verfügbar").

## Monitoring

`podman exec capsa-api capsa stats` shows the database size and, per account, the
number of answers (in total and in the last 30 days), devices and the last answer;
`--json` for scripts. It notes accounts that pass 100,000 events, the point where
learning-state snapshots become worthwhile (SPEC 13).

## Backups

`capsa db backup` writes a consistent copy of the database (safe while the app is
running) to `/data/backups` in the data volume and keeps the newest 14. To run it
nightly as a systemd user service next to rootless podman (with rootful podman, i.e.
`sudo podman compose`, install the two files into `/etc/systemd/system/` instead and
use `sudo systemctl` without `--user`; lingering is not needed):

```sh
mkdir -p ~/.config/systemd/user
cp capsa-backup.service capsa-backup.timer ~/.config/systemd/user/
# with another instance name, set CAPSA_CONTAINER in the .service file
systemctl --user daemon-reload
systemctl --user enable --now capsa-backup.timer
loginctl enable-linger "$USER"    # run timers without being logged in
```

The copies live in the volume (`podman volume inspect capsa_data` shows its path);
include that folder in the server's regular backup.

To restore: stop the API, replace the database with a backup, start again.

```sh
podman stop capsa-api
podman run --rm -v capsa_data:/data docker.io/library/alpine sh -c \
  'cp /data/backups/capsa-YYYYMMDD-HHMMSS.sqlite /data/capsa.sqlite && rm -f /data/capsa.sqlite-wal /data/capsa.sqlite-shm'
podman start capsa-api
```

## ACME certificates instead of a wildcard certificate

Add the resolver to both routers, for example in a `compose.override.yaml`:

```yaml
services:
  api:
    labels:
      - traefik.http.routers.capsa-api.tls.certresolver=letsencrypt
  web:
    labels:
      - traefik.http.routers.capsa-web.tls.certresolver=letsencrypt
```

## Security notes

- No ports are published; only Traefik reaches the containers.
- The API trusts `X-Forwarded-For` from `CAPSA_TRUSTED_PROXIES` (default `*`, i.e.
  every peer on the Traefik network) to see client addresses for the login rate limit.
  Narrow it to Traefik's address or network if other containers share that network.
- The session cookie is `Secure`, `HttpOnly` and `SameSite=Strict`; the app must be
  served over HTTPS.

## Later: Quadlet

Moving to podman Quadlet (systemd units) means one `.container` file per service with
the same image, volume, network and labels; labels are written out literally there,
since Quadlet does not substitute `.env` variables in labels.
