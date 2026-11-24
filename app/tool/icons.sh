#!/bin/sh
# Render the app icons for Android, iOS and the web from the PWA's icon, so both
# clients look the same: app/tool/icons.sh (needs rsvg-convert from librsvg).
set -eu
cd "$(dirname "$0")/.."
src=../web/public/icon.svg
bg='#1d4e5f'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The drawing without its rounded background, for layers and masks.
drawing=$(sed -e '/<svg /d' -e '/<\/svg>/d' -e '/<rect width="512" height="512"/d' "$src")

# Android's adaptive icons are 108dp, of which a launcher shows the middle 72dp and
# only a 66dp circle is safe from masks: fit the 512 box into those 66dp.
pad=163 # (512 * 108 / 66 - 512) / 2
box="-$pad -$pad $((512 + 2 * pad)) $((512 + 2 * pad))"
cat >"$tmp/foreground.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="$box">
$drawing
</svg>
EOF
# Full-bleed square, for masks applied by the platform (web maskable, iOS).
cat >"$tmp/maskable.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="$box">
<rect x="-$pad" y="-$pad" width="100%" height="100%" fill="$bg"/>
$drawing
</svg>
EOF
cat >"$tmp/square.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" fill="$bg"/>
$drawing
</svg>
EOF

render() { # svg size out
  rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
}

# Android: adaptive icon (8.0+) plus the plain icon for older versions.
res=android/app/src/main/res
for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  name=${d%%:*}
  scale=${d#*:}
  px() { python3 -c "print(round($1 * $scale))"; }
  mkdir -p "$res/mipmap-$name"
  render "$src" "$(px 48)" "$res/mipmap-$name/ic_launcher.png"
  render "$tmp/foreground.svg" "$(px 108)" "$res/mipmap-$name/ic_launcher_foreground.png"
done
mkdir -p "$res/mipmap-anydpi-v26"
cat >"$res/mipmap-anydpi-v26/ic_launcher.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF
cat >"$res/values/ic_launcher_background.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$bg</color>
</resources>
EOF

# Web: as the PWA's icons.
render "$src" 64 web/favicon.png
render "$src" 192 web/icons/Icon-192.png
render "$src" 512 web/icons/Icon-512.png
render "$tmp/maskable.svg" 192 web/icons/Icon-maskable-192.png
render "$tmp/maskable.svg" 512 web/icons/Icon-maskable-512.png

# iOS rounds the corners itself and wants no transparency; keep the existing sizes.
for f in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  size=$(basename "$f" .png | sed -E 's/Icon-App-([0-9.]+)x[0-9.]+@([0-9])x/\1 * \2/')
  render "$tmp/square.svg" "$(python3 -c "print(round($size))")" "$f"
done
# rsvg-convert writes RGBA; iOS rejects an alpha channel on the store icon.
if command -v magick >/dev/null; then
  for f in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
    magick "$f" -background "$bg" -alpha remove -alpha off "$f"
  done
fi
