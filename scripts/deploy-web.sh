#!/bin/bash
# Build the Flutter web version and copy it to your server (set up once with
# server/web/install.sh):  HEVYFIN_HOST=root@my-server ./scripts/deploy-web.sh
# Optional: NIQL_URL=/niql turns on "Ask" (docs/niql.md); HEVYFIN_DEST changes the folder.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=${HEVYFIN_HOST:?Set HEVYFIN_HOST, e.g. root@my-server}
DEST=${HEVYFIN_DEST:-/srv/hevyfin-web/site/}
# CanvasKit comes from the server itself, not Google's CDN.
flutter build web --release --no-web-resources-cdn ${NIQL_URL:+--dart-define=NIQL_URL=$NIQL_URL}
# Compressed copies for nginx's gzip_static: about a third of the size to download.
find build/web -type f \( -name '*.js' -o -name '*.wasm' -o -name '*.json' -o -name '*.html' -o -name '*.otf' -o -name '*.ttf' -o -name '*.bin' \) -exec gzip -9 -k -f {} +
rsync -az --delete --info=stats1 build/web/ "$HOST:$DEST"
echo "Deployed to $HOST:$DEST (port 8090 on that machine)"
