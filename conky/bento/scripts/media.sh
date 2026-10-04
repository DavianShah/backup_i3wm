#!/bin/bash
# Cached media info for Conky (playerctl first, mpd/mpc fallback).
# Usage: media.sh status|title|artist|position
#
# All four ${execi} fields share one cache, so the D-Bus/MPD poll runs at
# most once per TTL seconds instead of once per field.

CACHE="${XDG_RUNTIME_DIR:-/tmp}/conky-media-${USER}.cache"
TTL=2

now=$(date +%s)
mtime=0
[ -f "$CACHE" ] && mtime=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)

if [ $(( now - mtime )) -ge "$TTL" ]; then
  # Serialize concurrent field lookups: first writer polls, rest reuse.
  exec 9>"${CACHE}.lock"
  flock 9 2>/dev/null

  mtime=0
  [ -f "$CACHE" ] && mtime=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  if [ $(( now - mtime )) -ge "$TTL" ]; then
    st="" ar="" ti="" po=""

    meta=$(playerctl metadata --format '{{status}}|{{artist}}|{{title}}' 2>/dev/null)
    if [ -n "$meta" ]; then
      st=${meta%%|*}
      rest=${meta#*|}
      ar=${rest%%|*}
      ti=${rest#*|}
      po=$(playerctl position 2>/dev/null | cut -d. -f1)
    else
      # MPD fallback
      mpc_out=$(mpc status 2>/dev/null)
      if [ -n "$mpc_out" ]; then
        line2=$(printf '%s\n' "$mpc_out" | sed -n 2p)
        case "$line2" in
          '[playing]'*) st="Playing" ;;
          '[paused]'*)  st="Paused"  ;;
          *)            st="Stopped" ;;
        esac
        po=$(printf '%s\n' "$line2" | awk '{
          for (i = 1; i <= NF; i++)
            if ($i ~ /^[0-9]+:[0-9]+\/[0-9]+:[0-9]+$/) {
              split($i, a, "/"); print a[1]; exit
            }
        }')
        meta=$(mpc -f '%artist%|%title%' current 2>/dev/null)
        ar=${meta%%|*}
        ti=${meta#*|}
      fi
    fi

    printf '%s|%s|%s|%s\n' "$st" "$ar" "$ti" "$po" \
      > "${CACHE}.$$" && mv "${CACHE}.$$" "$CACHE"
  fi
fi

IFS='|' read -r st ar ti po < "$CACHE" 2>/dev/null

case "$1" in
  status)
    case "$st" in
      Playing) printf '%s\n' "󰐊 Playing" ;;
      Paused)  printf '%s\n' "󰏤 Paused" ;;
      *)       printf '%s\n' "󰝚 Nothing playing" ;;
    esac
    ;;
  title)
    [ -z "$ti" ] && ti="Nothing playing"
    printf '%s\n' "${ti:0:34}"
    ;;
  artist)
    [ -z "$ar" ] && ar="playerctl / mpd"
    printf '%s\n' "${ar:0:26}"
    ;;
  position)
    if [ -n "$po" ]; then
      s=${po%%.*}
      printf '%d:%02d\n' $(( s / 60 )) $(( s % 60 ))
    else
      printf '%s\n' "--:--"
    fi
    ;;
  *)
    echo "Usage: $0 status|title|artist|position" >&2
    exit 1
    ;;
esac
