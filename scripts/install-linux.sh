#!/bin/bash
# Build Hevyfin for Linux and install it for the current user (menu entry + icon).
# Run from a shell that has Flutter and the mpv development package (mpv-devel / libmpv-dev),
# for example a toolbox or distrobox; the result also runs on the host.
# libmpv and a few libraries an immutable host may lack are bundled in lib/mpv, and a launcher
# points the loader there.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build linux --release
B=build/linux/x64/release/bundle
mkdir -p $B/lib/mpv
MPV=$(ldconfig -p | awk '/libmpv\.so\.2 /{print $NF; exit}')
[ -n "$MPV" ] || { echo "libmpv.so.2 not found: install mpv's library first" >&2; exit 1; }
cp -L "$MPV" $B/lib/mpv/
for s in liblua-5.1.so libmujs.so.0.1 libuchardet.so.0 libvapoursynth-script.so.0 libxevdb.so.0 libxeveb.so.0 libXpresent.so.1 libnghttp3.so.9; do
  p=$(ldd "$MPV" | awk -v s=$s '$1==s{print $3}')
  [ -n "$p" ] && cp -L "$p" $B/lib/mpv/
done
DEST="$HOME/.local/opt/hevyfin"
rm -rf "$DEST" && mkdir -p "$DEST" && cp -a $B/. "$DEST/"
cat > "$DEST/hevyfin.sh" <<SH
#!/bin/sh
export LD_LIBRARY_PATH="$DEST/lib/mpv\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$DEST/hevyfin" "\$@"
SH
chmod +x "$DEST/hevyfin.sh"
install -Dm644 branding/icon-512.png "$HOME/.local/share/icons/hicolor/512x512/apps/io.github.nickhemeryckehevan.hevyfin.png"
install -Dm644 branding/icon-256.png "$HOME/.local/share/icons/hicolor/256x256/apps/io.github.nickhemeryckehevan.hevyfin.png"
# The file name matches the GTK application id so Wayland shows the right icon.
cat > "$HOME/.local/share/applications/io.github.nickhemeryckehevan.hevyfin.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Hevyfin
GenericName=Video Player
Comment=Watch your Jellyfin library and request more through Seerr
Exec=$DEST/hevyfin.sh
Icon=io.github.nickhemeryckehevan.hevyfin
Terminal=false
Categories=AudioVideo;Video;Player;
Keywords=jellyfin;movies;shows;netflix;seerr;
StartupWMClass=io.github.nickhemeryckehevan.hevyfin
DESKTOP
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Installed to $DEST. Launch Hevyfin from the app menu."
