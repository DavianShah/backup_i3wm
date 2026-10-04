#!/usr/bin/env bash
# Polybar network label: wifi logo on WLAN, ethernet logo (U+F6FF) on a wired
# link, offline logo when nothing is connected. Also prints downspeed as the
# rx_bytes delta since the previous poll (polybar runs this every 5s).
# Glyphs are written as \u escapes: literal private-use chars get mangled.

CLICK='%{A1:setsid -f ~/.config/rofi/scripts/netmenu.sh >/dev/null 2>&1 &:}'
ICON_WIFI=$'\uFAA8'   # wifi
ICON_ETH=$'\uF6FF'    # ethernet
ICON_OFF=$'\uEA17'   # offline (original disconnected logo)

eth=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}')
wifi=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected"{print $1; exit}')
dev=${eth:-${wifi:-}}

if [ -z "$dev" ]; then
  printf '%s\n' "%{F#FFFFFF}${ICON_OFF}%{F-}${CLICK} Offline%{A}"
  exit 0
fi

# Downspeed: (rx bytes delta) / (seconds elapsed) since last run.
speed='0B/s'
rx=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)
now=$(date +%s)
state="${XDG_RUNTIME_DIR:-/tmp}/polybar-netspeed-$dev"
prev=$(cat "$state" 2>/dev/null)
printf '%s %s\n' "$rx" "$now" >"$state"
if [ -n "$prev" ]; then
  read -r prx pt <<<"$prev"
  dt=$((now - pt))
  if [ "$dt" -gt 0 ]; then
    delta=$((rx - prx))
    [ "$delta" -lt 0 ] && delta=0
    speed=$(LC_ALL=C numfmt --to=iec-i --suffix=B/s "$delta" 2>/dev/null || echo 0B/s)
  fi
fi

icon=$ICON_WIFI
essid=''
if [ -n "$eth" ]; then
  icon=$ICON_ETH
elif [ -n "$wifi" ]; then
  essid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
fi

printf '%s\n' "%{F#FFFFFF}${icon}%{F-}${CLICK} ${essid} ${speed}%{A}"
