# Hosting the web version

The browser can't talk to Jellyfin and Seerr on other addresses without CORS, and it can't keep
Seerr's sign-in cookie for another site. So the web version is served by a small nginx that also
passes Jellyfin, Seerr (and optionally the recommendation service) through on **the same address**:

```
http://your-server:8090/            Flutter web build        (scripts/deploy-web.sh)
http://your-server:8090/next/       Vue browser version      (browser/scripts/deploy.sh)
http://your-server:8090/get/        phones: download the Android app
http://your-server:8090/apk/        the APK + latest.json
http://your-server:8090/jellyfin/   → JELLYFIN_UPSTREAM
http://your-server:8090/seerr/      → SEERR_UPSTREAM
http://your-server:8090/niql/       → NIQL_UPSTREAM (only if set)
```

## Setup (podman + systemd)

```sh
# on the server, as root, from a copy of server/web/
JELLYFIN_UPSTREAM=http://127.0.0.1:8096 SEERR_UPSTREAM=http://127.0.0.1:5055 ./install.sh

# on your computer
HEVYFIN_HOST=root@your-server ./scripts/deploy-web.sh
HEVYFIN_HOST=root@your-server ./browser/scripts/deploy.sh
```

`install.sh` fills `nginx.conf` in with your upstreams, installs the `hevyfin-web` quadlet
(nginx:stable, host network, port 8090) and starts it. Files live in `/srv/hevyfin-web/`
(`HEVYFIN_WEB_DIR` changes that). Without podman, run any nginx with the filled-in `nginx.conf`
as its site config and the same folders.

## Why the socket needs nginx

Jellyfin's live socket (remote control, Watch together) wants the sign-in in an
`Authorization` header, which a browser can't send on a WebSocket, and Jellyfin refuses it in the
address. The page sends it as `api_key`, and nginx's `location = /jellyfin/socket` turns it into
the header. Without that block, the browser loses remote control; everything else still works.

## Phones: `/get/`

Phones and tablets that open the web version are sent to `/get/`, a page with a download button
for the Android app (iPhones get a note that it's Android only; `?web=1` opens the web version
anyway). Put an APK and a `latest.json` next to it in `/srv/hevyfin-web/apk/`:

```json
{"file": "hevyfin-1.0.0-arm64-v8a.apk", "version": "1.0.0", "size": 41234567, "published": "2026-10-29"}
```

Build the APK yourself ([building.md](building.md#android-phones-tablets-and-tv)). Without `latest.json`, the page says there's no app
to download yet.

## Keep it private

Every stream, subtitle and socket address carries a sign-in key, so access logs are off.
Keep port 8090 on your LAN, or reach it over a VPN (WireGuard, Tailscale, …). If you do put it
on the internet, put an HTTPS reverse proxy in front of it and keep Jellyfin's own security up to date.
