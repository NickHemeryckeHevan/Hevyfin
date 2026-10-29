#!/bin/bash
# Installs or updates Hevyfin Admin with podman + systemd (quadlets). Run as root from a copy
# of the repo's admin/ folder:   bash deploy/install.sh
# The first run writes /srv/hevyfin-admin/app.env from deploy/app.env.example with a fresh
# SECRET_KEY; fill in your services there and run it again. The panel listens on :8067.
# Keep it on your LAN or VPN: it controls accounts.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=${HEVYFIN_ADMIN_DIR:-/srv/hevyfin-admin}
VERSION=$(python3 -c "import json; print(json.load(open('frontend/package.json'))['version'])")
podman build -q -t "localhost/hevyfin-admin:$VERSION" . >/dev/null
install -d -m 700 "$DIR"
install -d -m 755 "$DIR/watch"
if [ ! -f "$DIR/app.env" ]; then
  umask 077
  sed "s/^SECRET_KEY=$/SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')/" deploy/app.env.example > "$DIR/app.env"
  echo "Wrote $DIR/app.env: fill in JELLYFIN_URL (and any optional services), then run this again."
  exit 0
fi
sed "s/VERSION/$VERSION/; s|/srv/hevyfin-admin|$DIR|g" deploy/hevyfin-admin.container > /etc/containers/systemd/hevyfin-admin.container
systemctl daemon-reload
systemctl restart hevyfin-admin.service
echo "Hevyfin Admin $VERSION is on port 8067 of this machine."
echo "release-watch (optional, deploy/release-watch/) is not installed by this script."
