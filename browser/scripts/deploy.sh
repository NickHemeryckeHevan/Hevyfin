#!/bin/bash
# Builds the browser version and copies it to your server, next to the Flutter build at
# /next/ (server/web/nginx.conf):  HEVYFIN_HOST=root@my-server ./scripts/deploy.sh
# HEVYFIN_BASE=/ builds it for the site's root instead; VITE_NIQL_URL=/niql turns on "Ask".
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=${HEVYFIN_HOST:?Set HEVYFIN_HOST, e.g. root@my-server}
BASE=${HEVYFIN_BASE:-/next/}
DEST=${HEVYFIN_DEST:-/srv/hevyfin-web/next/}
npm ci --no-audit --no-fund
npm test
HEVYFIN_BASE=$BASE npm run build
# Compressed copies for nginx's gzip_static.
find dist -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' -o -name '*.svg' -o -name '*.json' \) -exec gzip -9 -k -f {} +
ssh "$HOST" "mkdir -p $DEST"
rsync -az --delete --info=stats1 dist/ "$HOST:$DEST"
# SELinux hosts need the right labels on the copied files.
ssh "$HOST" "command -v restorecon >/dev/null && restorecon -R $DEST || true"
echo "Deployed to $HOST:$DEST (http://<server>:8090$BASE)"
