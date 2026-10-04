#!/usr/bin/env bash
# make-header.sh - build the rofi launcher header strip from the real wallpaper.
#
# Renders ~/.config/nitrogen/bg-saved.cfg's wallpaper exactly the way nitrogen
# does for mode=5 (SET_ZOOM_FILL, SetBG::make_zoom_fill: integer cover scale,
# bilinear, centered crop), then crops the header box, bakes rounded corners
# as transparency. Output: ~/.cache/rofi-launcher/header.png (cache key =
# wallpaper path+mtime+mode+geometry+this script's mtime; fast no-op otherwise).
set -euo pipefail

# --- calibration (nudge if crop looks misaligned by eye) ---------------------
HEADER_DX=0          # px added to screen X of the header box
HEADER_DY=0          # px added to screen Y of the header box

# --- header box geometry (measured under Xvfb, 1920x1200, launcher.rasi) ----
HEADER_X=474         # (1920-1000)/2 win x + 1 win border + 12 pad + 1 mainbox
HEADER_Y=307         # (1200-615)/2 win y + 1 win border + 12 pad + 1 mainbox
HEADER_W=972         # 1000 - 2*1 border - 2*12 padding - 2*1 mainbox border
HEADER_H=195         # header box: window 615 - 26 win - 2 mainbox - 12 gap - 380 list
HEADER_RADIUS=18     # launcher.rasi header border-radius
SCREEN_W=1920
SCREEN_H=1200

CFG="${NITROGEN_CFG:-$HOME/.config/nitrogen/bg-saved.cfg}"
CACHE_DIR="$HOME/.cache/rofi-launcher"
OUT="$CACHE_DIR/header.png"
KEY="$CACHE_DIR/header.key"

die() { echo "make-header: $*" >&2; exit 1; }

[ -r "$CFG" ] || die "no nitrogen config at $CFG"
WP=$(sed -n 's/^file=//p' "$CFG" | head -n1)
MODE=$(sed -n 's/^mode=//p' "$CFG" | head -n1)
if [ -z "$WP" ] || [ ! -r "$WP" ]; then die "wallpaper missing: ${WP:-<none>}"; fi

mkdir -p "$CACHE_DIR"
stamp=$(stat -c %Y "$WP" 2>/dev/null || echo 0)
key="$WP|$stamp|$MODE|$HEADER_DX|$HEADER_DY|$HEADER_X|$HEADER_Y|$HEADER_W|$HEADER_H|$HEADER_RADIUS|$(stat -c %Y "$0")"

# fast path: cached and nothing changed -> no ImageMagick work, no delay
if [ -f "$OUT" ] && [ -f "$KEY" ] && [ "$(cat "$KEY")" = "$key" ]; then
    exit 0
fi

command -v convert >/dev/null 2>&1 || die "ImageMagick not installed (sudo apt install imagemagick)"

# nitrogen supports only mode 5 here; anything else falls back to zoom-fill
[ "$MODE" = 5 ] || echo "make-header: nitrogen mode=$MODE unsupported, rendering mode 5 (zoom-fill)" >&2

cx=$((HEADER_X + HEADER_DX))
cy=$((HEADER_Y + HEADER_DY))
if [ "$cx" -lt 0 ] || [ "$cy" -lt 0 ] ||
  [ $((cx + HEADER_W)) -gt "$SCREEN_W" ] || [ $((cy + HEADER_H)) -gt "$SCREEN_H" ]; then
    die "crop ${cx},${cy} ${HEADER_W}x${HEADER_H} outside ${SCREEN_W}x${SCREEN_H} screen"
fi

# SetBG::make_zoom_fill integer math: fit width, else fit height, center crop
ow=$(identify -format '%w' "$WP")
oh=$(identify -format '%h' "$WP")
w=$SCREEN_W
h=$((SCREEN_W * oh / ow))
x=0
y=$(((h - SCREEN_H) / 2))
if [ "$h" -lt "$SCREEN_H" ]; then
    y=0
    h=$SCREEN_H
    w=$((SCREEN_H * ow / oh))
    x=$(((w - SCREEN_W) / 2))
fi

# render screen, crop header box, bake r=HEADER_RADIUS corners as alpha
convert "$WP" -resize "${w}x${h}!" \
    -crop "${SCREEN_W}x${SCREEN_H}+${x}+${y}" +repage \
    -crop "${HEADER_W}x${HEADER_H}+${cx}+${cy}" +repage \
    -alpha set \
    \( -size "${HEADER_W}x${HEADER_H}" xc:none -fill white \
       -draw "roundrectangle 0,0,$((HEADER_W - 1)),$((HEADER_H - 1)),${HEADER_RADIUS},${HEADER_RADIUS}" \) \
    -compose DstIn -composite \
    "$OUT.tmp.png"

mv "$OUT.tmp.png" "$OUT"
printf '%s\n' "$key" >"$KEY"
