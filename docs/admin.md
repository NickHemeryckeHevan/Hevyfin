# Hevyfin Admin

A web panel for the admins of a Jellyfin server that people watch with Hevyfin. Sign in with a
**Jellyfin administrator** account; anyone else is turned away. Account changes are made with
your own sign-in; the other services use the API keys in its `app.env`.

| Tab | What you can do | Needs |
|---|---|---|
| **People** | set or reset passwords (and sign them out everywhere), see and remove their devices, switch an account off, age limit, libraries, viewing hours, a streaming cap away from home, request rights and quotas, add someone (Jellyfin and Seerr) | Jellyfin (Seerr for request rights) |
| **Requests** | approve or decline what people asked for, request something for someone | Seerr |
| **Now watching** | who's streaming what, whether it's transcoded and why, stop a stream, message every screen | Jellyfin |
| **Server health** | disk space, missing titles and download problems, freeing up space by deleting films/shows (files too) | Sonarr and/or Radarr |
| **Server health: download tools** | qBittorrent status, indexers (test and switch back on), "search for missing now", *On the lookout* | qBittorrent, Prowlarr, release-watch: **all optional, all off by default** |

In Server health, every card whose service isn't configured is left out. Without Seerr, the
Requests tab and the request rights just say Seerr isn't set up.

## Install (podman + systemd)

```sh
# on the server, as root, from a copy of admin/
bash deploy/install.sh        # 1st run: writes /srv/hevyfin-admin/app.env and stops
$EDITOR /srv/hevyfin-admin/app.env
bash deploy/install.sh        # builds the image, installs the quadlet, starts it on :8067
```

`deploy/app.env.example` lists every setting. Only `SECRET_KEY` (made for you) and
`JELLYFIN_URL` are needed. From inside the container your host is `host.containers.internal`;
to reach other containers by name, put it on their network (`Network=` in
`deploy/hevyfin-admin.container`).

The panel controls accounts: **keep it on your LAN or VPN**, never on the open internet.

## release-watch (optional)

A daily job that searches your Prowlarr indexers for releases Sonarr/Radarr can't recognise
themselves (a particular edition, say) and lists them under *On the lookout*. It never
downloads anything. It's not installed by `install.sh`. To use it:

```sh
install -m 755 deploy/release-watch/release-watch.py /usr/local/sbin/
install -m 644 deploy/release-watch/release-watch.example.json /etc/release-watch.json   # edit it
printf 'PROWLARR_URL=http://127.0.0.1:9696\nPROWLARR_KEY=…\n' > /etc/release-watch.env && chmod 600 /etc/release-watch.env
install -m 644 deploy/release-watch/release-watch.{service,timer} /etc/systemd/system/
systemctl enable --now release-watch.timer
```

Only use the download tools for content you have the right to download. See
[DISCLAIMER.md](../DISCLAIMER.md).
