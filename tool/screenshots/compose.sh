#!/usr/bin/env bash
# Compose iBuild store shots: a real demo-mode screenshot (capture.mjs), rounded
# and shadowed, over an OpenArt backdrop, under a caption in Overpass, the
# app's own typeface. Only the backdrop is generated; the app UI never is
# (App Store Review Guideline 2.3.3).
#
# Usage: tool/screenshots/compose.sh <captures-dir> <backdrops-dir> <out-dir>
#   captures-dir  has phone/ and tablet/ from capture.mjs
#   backdrops-dir has bg1.jpg .. bg3.jpg (9:16)
set -euo pipefail

CAPTURES="$1"; BACKDROPS="$2"; OUT="$3"
FONT_DIR="${FONT_DIR:-/tmp/ibuild-fonts}"
FONT_HEAD="$FONT_DIR/Overpass-800.ttf"
FONT_SUB="$FONT_DIR/Overpass-600.ttf"
# Static weights: ImageMagick cannot pick a weight off a variable font.
fetch_font() {
  [ -f "$2" ] && return
  mkdir -p "$FONT_DIR"
  url=$(curl -fsS -A "Mozilla/4.0" "https://fonts.googleapis.com/css2?family=Overpass:wght@$1" \
    | grep -o 'https://[^)]*\.ttf' | head -1)
  curl -fsS -o "$2" "$url" || { echo "could not download Overpass $1"; exit 1; }
}
fetch_font 800 "$FONT_HEAD"
fetch_font 600 "$FONT_SUB"

WHITE="#FFFFFF"
AMBER="#FFB627"

# name:width:height:captures-subdir
TARGETS=(
  "apple_69:1290:2796:phone"      # App Store iPhone 6.9"
  "apple_13:2064:2752:tablet"     # App Store iPad 13" (required: the app ships on iPad)
  "play_phone:1080:1920:phone"    # Google Play phone
  "play_tablet:1600:2560:tablet"  # Google Play 10" tablet
)

# capture|headline|subhead|backdrop
PANELS=(
  "01_dashboard|Every build,\non the line|Fetch, test, build and upload, live|bg1.jpg"
  "02_build|Logs that\nfollow along|Tap a step to watch it run|bg2.jpg"
  "03_history|Every build\nat a glance|Pass, fail and timing for each branch|bg3.jpg"
  "04_testflight|Straight to\nyour testers|See the moment TestFlight is ready|bg1.jpg"
  "05_android|iOS and\nAndroid too|Android builds land in Play as drafts|bg2.jpg"
)

for target in "${TARGETS[@]}"; do
  IFS=: read -r tname W H sub <<<"$target"
  mkdir -p "$OUT/$tname"
  # Type sized off whichever side asks for more, so tablets are not lost.
  head_pt=$((H * 38 / 1000)); [ $((W * 62 / 1000)) -gt $head_pt ] && head_pt=$((W * 62 / 1000))
  sub_pt=$((H * 16 / 1000));  [ $((W * 27 / 1000)) -gt $sub_pt ]  && sub_pt=$((W * 27 / 1000))
  head_y=$((head_pt * 131 / 100))
  sub_y=$((head_y + head_pt * 250 / 100))
  cap_h=$((sub_y + sub_pt * 220 / 100))
  free=$((H - cap_h))
  dev_wmax=$((W * 72 / 100))
  dev_hmax=$((free * 86 / 100))

  i=1
  for panel in "${PANELS[@]}"; do
    IFS='|' read -r shot headline subhead backdrop <<<"$panel"
    src="$CAPTURES/$sub/$shot.png"
    out="$OUT/$tname/$(printf '%02d' $i)_${shot#*_}.png"
    tmp="$(mktemp -d)"
    magick "$BACKDROPS/$backdrop" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" "$tmp/bg.png"
    # A navy scrim behind the caption so it never sits on a bright glint.
    magick -size "${W}x$((cap_h * 13 / 10))" gradient:"rgba(14,22,40,0.92)-rgba(14,22,40,0)" "$tmp/scrim.png"
    magick "$tmp/bg.png" "$tmp/scrim.png" -gravity north -composite "$tmp/bg.png"
    magick "$src" -resize "${dev_wmax}x${dev_hmax}" "$tmp/shot.png"
    sw=$(identify -format "%w" "$tmp/shot.png"); sh=$(identify -format "%h" "$tmp/shot.png")
    radius=$((sw * 6 / 100))
    magick -size "${sw}x${sh}" xc:none -draw "roundrectangle 0,0,$((sw-1)),$((sh-1)),$radius,$radius" "$tmp/mask.png"
    magick "$tmp/shot.png" -alpha set "$tmp/mask.png" -compose DstIn -composite "$tmp/rounded.png"
    magick "$tmp/rounded.png" \( +clone -background black -shadow 60x$((W/36))+0+$((H/120)) \) \
      +swap -background none -layers merge +repage "$tmp/device.png"
    dh=$(identify -format "%h" "$tmp/device.png")
    dev_y=$((cap_h + (free - dh) / 2))
    magick "$tmp/bg.png" "$tmp/device.png" -gravity north -geometry "+0+${dev_y}" -composite \
      -font "$FONT_HEAD" -pointsize "$head_pt" -fill "$WHITE" -gravity north \
      -interline-spacing $((head_pt / 10)) -annotate "+0+${head_y}" "$(printf '%b' "$headline")" \
      -font "$FONT_SUB" -pointsize "$sub_pt" -fill "$AMBER" -annotate "+0+${sub_y}" "$subhead" \
      "$out"
    rm -rf "$tmp"
    echo "  $tname/$(basename "$out") $(identify -format '%wx%h' "$out")"
    i=$((i+1))
  done
done
