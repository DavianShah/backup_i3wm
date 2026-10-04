#!/bin/sh
# Refresh wallpaper-strip header (self-cached, no-op when wallpaper unchanged).
"$HOME/.config/rofi/scripts/make-header.sh" ||
  echo "make-header.sh failed; header may be stale" >&2
exec rofi -show drun \
  -modes "drun,filebrowser,run,window,calc:$HOME/.config/rofi/scripts/calc.sh" \
  -theme "$HOME/.config/rofi/launcher.rasi" \
  -window-title launcher
