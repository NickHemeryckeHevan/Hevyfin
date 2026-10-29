#!/bin/bash
# First-time setup of Hevyfin web on a Linux server with podman + systemd (quadlets). Run as
# root from a copy of this folder, then build and copy the site with scripts/deploy-web.sh
# (Flutter build, at /) and/or browser/scripts/deploy.sh (Vue build, at /next/).
#
#   JELLYFIN_UPSTREAM=http://127.0.0.1:8096 SEERR_UPSTREAM=http://127.0.0.1:5055 ./install.sh
#
# NIQL_UPSTREAM is optional (the recommendation service behind "Ask", docs/niql.md).
# The container uses the host network and listens on :8090. Keep that port on your LAN/VPN,
# or put an HTTPS reverse proxy in front of it (docs/self-hosting-web.md).
set -euo pipefail
cd "$(dirname "$0")"
: "${JELLYFIN_UPSTREAM:=http://127.0.0.1:8096}"
: "${SEERR_UPSTREAM:=http://127.0.0.1:5055}"
: "${NIQL_UPSTREAM:=}"
DIR=${HEVYFIN_WEB_DIR:-/srv/hevyfin-web}
export JELLYFIN_UPSTREAM SEERR_UPSTREAM NIQL_UPSTREAM

mkdir -p "$DIR/site" "$DIR/next" "$DIR/apk"
conf=$(envsubst '${JELLYFIN_UPSTREAM} ${SEERR_UPSTREAM} ${NIQL_UPSTREAM}' < nginx.conf)
# Without a recommendation service, leave its location out.
[ -n "$NIQL_UPSTREAM" ] || conf=$(sed '/# NIQL-BEGIN/,/# NIQL-END/d' <<<"$conf")
printf '%s\n' "$conf" > "$DIR/nginx.conf"
sed "s|/srv/hevyfin-web|$DIR|g" hevyfin-web.container > /etc/containers/systemd/hevyfin-web.container
systemctl daemon-reload
systemctl start hevyfin-web.service
echo "Hevyfin web is on port 8090 of this machine. If a firewall is on, open 8090/tcp for your LAN only."
