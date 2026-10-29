# Hevyfin Admin

Accounts, requests, who's watching and server health in one panel, for the admins of a Jellyfin
server people watch with Hevyfin. Flask backend + Vue 3 page, shipped as one container.

See **[docs/admin.md](../docs/admin.md)** for what it does, setup and settings, and
[docs/building.md](../docs/building.md#admin-panel-admin) for development.

```sh
bash deploy/install.sh     # podman + systemd; first run writes /srv/hevyfin-admin/app.env
```

The download tools (qBittorrent, Prowlarr, release-watch) are optional and off unless you set
them up. Only use them for content you have the right to download ([DISCLAIMER.md](../DISCLAIMER.md)).
