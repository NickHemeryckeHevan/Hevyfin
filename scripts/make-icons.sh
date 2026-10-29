#!/bin/bash
# Render the Android launcher icons and the Linux PNGs from branding/*.svg (needs rsvg-convert).
set -euo pipefail
cd "$(dirname "$0")/.."
R=android/app/src/main/res
for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  n=${d%%:*}; f=${d##*:}
  mkdir -p $R/mipmap-$n
  rsvg-convert -w $(python3 -c "print(int(48*$f))") branding/icon.svg -o $R/mipmap-$n/ic_launcher.png
  rsvg-convert -w $(python3 -c "print(int(108*$f))") branding/foreground.svg -o $R/mipmap-$n/ic_launcher_foreground.png
done
mkdir -p $R/mipmap-anydpi-v26 $R/values
cat > $R/mipmap-anydpi-v26/ic_launcher.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML
cat > $R/values/ic_launcher_background.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0A0A0A</color>
</resources>
XML
# Android TV home-screen banner (320x180 dp).
mkdir -p $R/drawable-xhdpi
rsvg-convert -w 640 branding/tv-banner.svg -o $R/drawable-xhdpi/tv_banner.png
rsvg-convert -w 512 branding/icon.svg -o branding/icon-512.png
rsvg-convert -w 256 branding/icon.svg -o branding/icon-256.png
# The web version's tab icon and install icons.
rsvg-convert -w 32 branding/icon.svg -o web/favicon.png
for n in 192 512; do
  rsvg-convert -w $n branding/icon.svg -o web/icons/Icon-$n.png
  rsvg-convert -w $n -b '#0A0A0A' branding/foreground.svg -o web/icons/Icon-maskable-$n.png
done
echo "Icons rendered."
